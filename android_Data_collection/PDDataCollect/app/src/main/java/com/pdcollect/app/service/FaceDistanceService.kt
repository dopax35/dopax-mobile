package com.pdcollect.app.service

import android.app.Notification
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.pdcollect.app.PDCollectApp
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.ui.MainActivity
import com.pdcollect.app.util.Constants
import com.pdcollect.app.util.PermissionUtils

/**
 * Foreground service for passive face-distance capture.
 *
 * Depending on the selected mode, sampling runs only when:
 *   1. The screen is ON.
 *   2. Either dopa-X itself is in the foreground, or another real app is in the foreground.
 */
class FaceDistanceService : LifecycleService() {

    private lateinit var dataManager: DataManager
    private lateinit var profile: UserProfile
    private var recorder: FaceDistanceRecorder? = null
    private var foregroundServiceStarted = false
    /** Wall-clock ms when onStartCommand ran — used for the screen-on fallback timer. */
    private var serviceStartedAtMs = 0L
    /** Handler used to schedule the ALWAYS-mode screen-on fallback retry. */
    private val fallbackHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val fallbackRetryRunnable = Runnable { startRecorderIfNeeded() }

    // --- gate flags ---
    /** True while the display is on. */
    private var screenOn = true
    private var dopaxInForeground = false

    /**
     * Package name of the current foreground app as reported by
     * [DataAccessibilityService].  Empty string means "no foreground app known"
     * (treated as not-in-foreground to be conservative).
     *
     * System packages that indicate an idle/locked state are normalized to "".
     */
    private var foregroundPackage: String = ""

    // Packages that indicate the device is idle or locked — treat them as
    // "no app in foreground" so we stop sampling.
    // Uses exact-match OR sub-package match (e.g. "com.android.launcher3.whatever")
    // to avoid false-positives while still covering nested activity classes.
    private val idlePackages = setOf(
        "android",
        "com.android.systemui",
        "com.android.launcher",
        "com.android.launcher3",
        "com.google.android.apps.nexuslauncher",
        "com.sec.android.app.launcher"
    )

    /** Returns true if [pkg] represents an idle/locked system UI state. */
    private fun isIdlePackage(pkg: String): Boolean =
        idlePackages.any { idle -> pkg == idle || pkg.startsWith("$idle.") }

    // -------------------------------------------------------------------------
    // Broadcast receivers
    // -------------------------------------------------------------------------

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    screenOn = false
                    stopRecorder()
                }
                Intent.ACTION_SCREEN_ON -> {
                    screenOn = true
                    startRecorderIfNeeded()
                }
            }
        }
    }

    private val foregroundAppReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val pkg = intent.getStringExtra(Constants.EXTRA_FOREGROUND_PACKAGE) ?: ""
            foregroundPackage = if (pkg.isEmpty() || isIdlePackage(pkg)) "" else pkg

            if (profile.faceDistanceMode == Constants.FACE_DISTANCE_MODE_ALWAYS) {
                if (foregroundPackage.isNotEmpty()) {
                    startRecorderIfNeeded()
                } else {
                    stopRecorder()
                }
            }
        }
    }

    private val appForegroundListener = object : PDCollectApp.AppForegroundListener {
        override fun onAppForegroundChanged(isInForeground: Boolean) {
            dopaxInForeground = isInForeground
            if (profile.faceDistanceMode == Constants.FACE_DISTANCE_MODE_APP_FOREGROUND) {
                if (isInForeground) {
                    startRecorderIfNeeded()
                } else {
                    stopRecorder()
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Lifecycle
    // -------------------------------------------------------------------------

    override fun onCreate() {
        super.onCreate()
        profile = UserProfile(this)
        dataManager = DataManager(this, profile)
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        screenOn = powerManager.isInteractive
        val app = application as? PDCollectApp
        dopaxInForeground = app?.isAppInForeground() == true
        app?.addAppForegroundListener(appForegroundListener)

        // System-broadcast receiver (must use regular Context.registerReceiver)
        registerReceiver(screenReceiver, IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        })

        // Local broadcast from DataAccessibilityService
        LocalBroadcastManager.getInstance(this).registerReceiver(
            foregroundAppReceiver,
            IntentFilter(Constants.ACTION_FOREGROUND_APP_CHANGED)
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                Constants.NOTIFICATION_ID_FACE,
                buildNotification(),
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            )
        } else {
            startForeground(Constants.NOTIFICATION_ID_FACE, buildNotification())
        }

        foregroundServiceStarted = true
        serviceStartedAtMs = System.currentTimeMillis()
        stopRecorder()
        startRecorderIfNeeded()
        // Schedule a deferred retry so that ALWAYS mode can fall back to
        // screen_on_fallback if Accessibility Service never delivers a broadcast.
        if (profile.faceDistanceMode == Constants.FACE_DISTANCE_MODE_ALWAYS) {
            fallbackHandler.removeCallbacks(fallbackRetryRunnable)
            fallbackHandler.postDelayed(fallbackRetryRunnable, FALLBACK_DELAY_MS)
        }
        return START_STICKY
    }

    // -------------------------------------------------------------------------
    // Recorder management
    // -------------------------------------------------------------------------

    /**
     * Starts the [FaceDistanceRecorder] only when the configured mode's gates are open.
     *
     * All early-returns now log the reason at WARN level so the logcat shows exactly
     * why capture did not start — previously these were all completely silent.
     *
     * ALWAYS mode has a screen-on fallback: if the screen has been on for ≥
     * [FALLBACK_DELAY_MS] but no foreground-package broadcast has arrived from
     * [DataAccessibilityService] (e.g. Accessibility Service not enabled), we start
     * the recorder anyway with context "screen_on_fallback" rather than recording
     * nothing indefinitely.
     */
    private fun startRecorderIfNeeded() {
        if (!foregroundServiceStarted) {
            android.util.Log.w(TAG, "startRecorderIfNeeded: foreground service not yet started — skipping")
            return
        }
        if (!screenOn) {
            android.util.Log.d(TAG, "startRecorderIfNeeded: screen off — skipping")
            return
        }
        if (recorder != null) return   // already running
        if (!PermissionUtils.hasCameraPermission(this)) {
            android.util.Log.w(TAG, "startRecorderIfNeeded: camera permission not granted — cannot record")
            return
        }

        val captureContext = when (profile.faceDistanceMode) {
            Constants.FACE_DISTANCE_MODE_APP_FOREGROUND -> {
                if (!dopaxInForeground) {
                    android.util.Log.d(TAG, "startRecorderIfNeeded: mode=app_foreground but dopa-X not in foreground — skipping")
                    return
                }
                Constants.FACE_DISTANCE_CONTEXT_APP_FOREGROUND
            }
            Constants.FACE_DISTANCE_MODE_ALWAYS -> {
                if (foregroundPackage.isNotEmpty()) {
                    Constants.FACE_DISTANCE_CONTEXT_ALWAYS
                } else {
                    // Accessibility Service hasn't reported a foreground package yet.
                    // If the screen has been on long enough that a broadcast would
                    // already have arrived had the service been enabled, fall back to
                    // recording with a distinct context label.
                    val msSinceStart = System.currentTimeMillis() - serviceStartedAtMs
                    if (msSinceStart >= FALLBACK_DELAY_MS) {
                        android.util.Log.w(
                            TAG,
                            "startRecorderIfNeeded: mode=always but no foreground-app broadcast after "
                                + "${msSinceStart}ms — Accessibility Service likely not enabled. "
                                + "Starting with screen_on_fallback context."
                        )
                        "screen_on_fallback"
                    } else {
                        android.util.Log.d(
                            TAG,
                            "startRecorderIfNeeded: mode=always, waiting for first foreground broadcast "
                                + "(${msSinceStart}ms / ${FALLBACK_DELAY_MS}ms elapsed)"
                        )
                        return
                    }
                }
            }
            else -> {
                android.util.Log.d(TAG, "startRecorderIfNeeded: mode=${profile.faceDistanceMode} — recorder not needed")
                return
            }
        }

        android.util.Log.i(TAG, "Starting FaceDistanceRecorder (context=$captureContext)")
        val prefs = getSharedPreferences(Constants.PREFS_NAME, android.content.Context.MODE_PRIVATE)
        recorder = FaceDistanceRecorder(
            context = this,
            lifecycleOwner = this,
            captureContext = captureContext,
            onSample = { sample ->
                dataManager.writeFaceDistanceData(sample.toCsvRow())
                // Stamp last-captured timestamp so the Settings UI can detect
                // a silently-stopped recorder and alert the participant.
                prefs.edit().putLong(PREF_LAST_SAMPLE_MS, System.currentTimeMillis()).apply()
            },
            onBlink  = { blink  -> dataManager.writeBlinkData(blink.toCsvRow()) },
            onError  = { android.util.Log.e(TAG, "Face distance capture failed", it) }
        ).also { it.start() }
    }

    private fun stopRecorder() {
        recorder?.stop()
        recorder = null
    }

    // -------------------------------------------------------------------------

    override fun onDestroy() {
        foregroundServiceStarted = false
        fallbackHandler.removeCallbacks(fallbackRetryRunnable)
        unregisterReceiver(screenReceiver)
        LocalBroadcastManager.getInstance(this).unregisterReceiver(foregroundAppReceiver)
        (application as? PDCollectApp)?.removeAppForegroundListener(appForegroundListener)
        stopRecorder()
        dataManager.closeAll()
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, Constants.CHANNEL_FACE)
            .setContentTitle("PD Data Collection")
            .setContentText("Face distance monitoring is ready.")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val TAG = "FaceDistanceService"
        /** SharedPreferences key written on every successful face-distance sample. */
        const val PREF_LAST_SAMPLE_MS = "face_distance_last_sample_ms"
        /**
         * How long to wait for the first foreground-app broadcast from
         * [DataAccessibilityService] before giving up and using the screen-on
         * fallback in ALWAYS mode.  10 seconds is enough for the accessibility
         * service to deliver its initial broadcast after the device unlocks,
         * while still being short enough that the first few minutes of a session
         * are not lost.
         */
        private const val FALLBACK_DELAY_MS = 10_000L

        fun start(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, FaceDistanceService::class.java)
            )
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, FaceDistanceService::class.java))
        }
    }
}

