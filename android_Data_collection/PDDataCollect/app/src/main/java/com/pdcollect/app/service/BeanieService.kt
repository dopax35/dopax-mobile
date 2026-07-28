package com.pdcollect.app.service

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.ui.MainActivity
import com.pdcollect.app.util.Constants
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.UUID
import com.pdcollect.app.logic.ActivityEngine
import com.pdcollect.app.logic.PostureEngine
import com.pdcollect.app.logic.MLPredictionStore
import com.pdcollect.app.logic.TskinSynthesizer

class BeanieService : Service() {

    internal enum class PushMode {
        NOTIFY,
        INDICATE
    }

    companion object {
        private const val TAG = "BeanieService"
        private const val RECONNECT_DELAY_MS = 10_000L
        private const val FAILURE_RECONNECT_DELAY_MS = 1_000L
        private const val AUTO_RECONNECT_SCAN_DELAY_MS = 5_000L
        private const val AUTO_RECONNECT_SCAN_RETRY_MS = 30_000L
        private const val SCAN_WINDOW_MS = 20_000L
        private const val CONNECTING_STALL_TIMEOUT_MS = 8_000L
        private const val LIVE_NOTIFICATION_MIN_INTERVAL_MS = 2_000L
        private const val STREAM_WARMUP_TIMEOUT_MS = 10_000L
        private const val READ_POLL_INTERVAL_MS = 1_500L
        private const val LIVE_START_RETRY_LIMIT = 2
        private const val TEMP_SAMPLE_STALE_MS = 120_000L
        // Live-stream stall watchdog: firmware cadence is one temperature packet every
        // ~5s (plus 25Hz IMU on hats that stream it), so 30s of silence on a "connected"
        // link means the stream is dead even though GATT never reported a disconnect.
        private const val LIVE_STALL_TIMEOUT_MS = 30_000L
        // If a connection never produces a single frame despite the warmup retries and
        // read-polling fallback, tear it down and reconnect rather than idling forever.
        private const val NEVER_STREAMED_TIMEOUT_MS = 60_000L
        private val ENABLE_NOTIFICATION_VALUE_BYTES = byteArrayOf(0x01, 0x00)
        private val ENABLE_INDICATION_VALUE_BYTES = byteArrayOf(0x02, 0x00)

        val BEANIE_SERVICE_UUID: UUID = UUID.fromString("12345678-90AB-4CDE-8123-1234567890AB")
        private val DATA_UUID: UUID = UUID.fromString("12345679-90AB-4CDE-8123-1234567890AB")
        private val CMD_UUID: UUID = UUID.fromString("1234567A-90AB-4CDE-8123-1234567890AB")
        private val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        const val ACTION_BEANIE_UPDATE = "com.pdcollect.app.BEANIE_UPDATE"
        const val EXTRA_CONNECTED = "extra_connected"
        const val EXTRA_STATUS = "extra_status"
        const val EXTRA_DEVICE_NAME = "extra_device_name"
        const val EXTRA_TSKIN_C = "extra_tskin_c"
        const val EXTRA_HEAT_FLUX = "extra_heat_flux"
        const val EXTRA_INNER_C = "extra_inner_c"
        const val EXTRA_OUTER_C = "extra_outer_c"
        const val EXTRA_BATTERY_PCT = "extra_battery_pct"
        const val EXTRA_ACTIVITY_LABEL = "extra_activity_label"
        const val EXTRA_ACTIVITY_CONFIDENCE = "extra_activity_confidence"

        const val STATUS_IDLE = "IDLE"
        const val STATUS_SCANNING = "SCANNING"
        const val STATUS_CONNECTING = "CONNECTING"
        const val STATUS_DISCOVERING = "DISCOVERING"
        const val STATUS_READY = "READY"
        const val STATUS_DISCONNECTED = "DISCONNECTED"

        fun start(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, BeanieService::class.java)
            )
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, BeanieService::class.java))
        }

        internal fun cccdEnableValueFor(properties: Int): ByteArray? {
            return pushModeFor(properties, preferIndications = false)?.let { cccdEnableValueFor(it) }
        }

        internal fun supportsRead(properties: Int): Boolean {
            return properties and BluetoothGattCharacteristic.PROPERTY_READ != 0
        }

        internal fun supportsIndicate(properties: Int): Boolean {
            return properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0
        }

        internal fun supportsNotify(properties: Int): Boolean {
            return properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0
        }

        internal fun pushModeFor(properties: Int, preferIndications: Boolean): PushMode? {
            return when {
                preferIndications && supportsIndicate(properties) -> PushMode.INDICATE
                supportsNotify(properties) -> PushMode.NOTIFY
                supportsIndicate(properties) -> PushMode.INDICATE
                else -> null
            }
        }

        internal fun cccdEnableValueFor(mode: PushMode): ByteArray {
            return when (mode) {
                PushMode.NOTIFY -> ENABLE_NOTIFICATION_VALUE_BYTES
                PushMode.INDICATE -> ENABLE_INDICATION_VALUE_BYTES
            }
        }
    }

    private lateinit var profile: UserProfile
    private lateinit var dataManager: DataManager
    private val handler = Handler(Looper.getMainLooper())

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bleScanner: BluetoothLeScanner? = null
    private var bluetoothGatt: BluetoothGatt? = null

    private var targetAddress: String = ""
    private var targetName: String = ""
    private var isScanning = false
    private var isConnected = false
    private var batteryPct: Int? = null
    private var lastTempSample: BeaniePacketParser.TemperatureSample? = null
    private var lastBroadcastSnapshot: BeanieStatusSnapshot? = null
    private var lastNotificationText: String = ""
    private var lastNotificationAtMs: Long = 0L
    private var packetParser = BeaniePacketParser(BeanieRegistry.profileForDevice(""))
    private var autoConnectPending = false
    private var activeDataCharacteristic: BluetoothGattCharacteristic? = null
    private var activeDataProperties: Int = 0
    private var activeCccdDescriptor: BluetoothGattDescriptor? = null
    private var activePushMode: PushMode? = null
    private var activeCommandCharacteristic: BluetoothGattCharacteristic? = null
    private var useReadPollingFallback = false
    private var preferIndicationFallback = false
    private var readRequestInFlight = false
    private var commandWriteInFlight = false
    private var commandWriteRetryCount = 0
    private var lastCommandWritePayload: ByteArray? = null
    private var liveStartRetryCount = 0
    private var lastStreamSetupAtMs: Long = 0L
    private var receivedFrameThisConnection = false
    // Wall-clock time of the last *accepted* frame (temp/IMU/battery) — drives the
    // live-stream stall watchdog in heartbeatRunnable. 0 = nothing yet this connection.
    private var lastAcceptedFrameAtMs: Long = 0L
    // After a STOP_ALL/barcode command echo (1-byte 0xB0), firmware sends 7 × 4-byte
    // barcode chunks that must be suppressed, not parsed (reference-app parity).
    private var barcodePacketsRemaining = 0
    private val incomingStreamBuffer = ArrayDeque<Byte>()
    private val commandWriteQueue = mutableListOf<ByteArray>()

    // ── Inference engines (Beanie upstream integration) ───────────────────────
    private lateinit var activityEngine: ActivityEngine
    private lateinit var postureEngine: PostureEngine
    // Smooths/denoises tSkin for the ML model only — CSV logging keeps the raw
    // per-packet sample.tskinC unchanged. One instance per service lifetime so its
    // warmup/worn-state tracking survives brief BLE reconnects (by design — see
    // TskinSynthesizer's own not-worn/put-on heuristics rather than resetting on
    // every disconnect).
    private val tskinSynthesizer = TskinSynthesizer()
    private var lastTskinUpdateAtMs: Long = 0L
    // IMU ring buffer: up to 1001 rows of [ax_g, ay_g, az_g, accelMag_g, gx_dps, gy_dps, gz_dps]
    private val imuRingBuffer = ArrayDeque<FloatArray>(1001)
    // Parallel timestamp deque (one entry per imuRingBuffer row, same push/pop order) so we
    // can report the true start time of whichever slice is actually fed to the model (the
    // last 250 rows), instead of the time the buffer first started filling.
    private val imuTimestamps = ArrayDeque<Long>(1001)
    private val reconnectRunnable = Runnable { connect() }
    private var scanFailCount = 0
    private val connectingStallRunnable = Runnable {
        val gatt = bluetoothGatt ?: return@Runnable
        if (isConnected) return@Runnable
        if (autoConnectPending) {
            Log.w(TAG, "Beanie autoConnect is still pending; starting scan fallback")
            if (!isScanning && !startScan()) {
                scheduleReconnect(FAILURE_RECONNECT_DELAY_MS)
            }
            return@Runnable
        }
        Log.w(TAG, "Beanie direct connection attempt stalled; closing GATT and retrying")
        if (bluetoothGatt === gatt) {
            bluetoothGatt = null
            isConnected = false
            resetActiveGattState(clearVitals = false)
        }
        @Suppress("MissingPermission")
        gatt.disconnect()
        @Suppress("MissingPermission")
        gatt.close()
        updateNotification("Beanie connect stalled - rescanning...", force = true)
        connect()
    }
    private val autoReconnectScanFallbackRunnable = Runnable {
        if (isConnected || isScanning || !autoConnectPending || bluetoothGatt == null) return@Runnable
        Log.i(TAG, "Beanie autoConnect still pending; scanning for advertising fallback")
        if (!startScan()) {
            scheduleReconnect(FAILURE_RECONNECT_DELAY_MS)
        }
    }
    private val scanTimeoutRunnable = Runnable {
        if (!isScanning) return@Runnable
        stopScan()
        if (isConnected) return@Runnable
        if (autoConnectPending && bluetoothGatt != null) {
            updateNotification("Beanie not found - waiting for advertising...", force = true)
            scheduleAutoReconnectScanFallback(AUTO_RECONNECT_SCAN_RETRY_MS)
            return@Runnable
        }
        scanFailCount++
        val backoff = (RECONNECT_DELAY_MS * (1 shl minOf(scanFailCount, 5))).coerceAtMost(300_000L)
        updateNotification("Beanie not found - retrying in ${backoff / 1000}s...", force = true)
        handler.removeCallbacks(reconnectRunnable)
        handler.postDelayed(reconnectRunnable, backoff)
    }
    private val streamWarmupRunnable = Runnable {
        if (receivedFrameThisConnection) return@Runnable
        if (liveStartRetryCount < LIVE_START_RETRY_LIMIT && activeCommandCharacteristic != null) {
            liveStartRetryCount++
            Log.w(TAG, "Beanie stream stayed silent after notification setup; retrying live-start command sequence")
            sendRtcAndResumeRecording()
            scheduleStreamWarmupTimeout()
            return@Runnable
        }
        recoverSilentStream("Beanie stream stayed silent after notification setup")
    }
    private val readPollRunnable = object : Runnable {
        override fun run() {
            if (!useReadPollingFallback || !isConnected) return
            if (readRequestInFlight) {
                scheduleNextReadPoll()
                return
            }
            pollDataCharacteristic()
        }
    }

    private val heartbeatRunnable = object : Runnable {
        override fun run() {
            checkLiveStreamStall()
            when {
                isConnected -> broadcastStatus(STATUS_READY)
                targetAddress.isNotBlank() -> broadcastStatus(STATUS_CONNECTING)
                else -> broadcastStatus(STATUS_IDLE)
            }
            handler.postDelayed(this, 15_000L)
        }
    }

    /**
     * Live-stream stall watchdog. The one-shot warmup watchdog only covers the window
     * before the *first* frame — once a frame arrived, nothing detected a stream that
     * later went silent while GATT still reported "connected" (peripheral firmware
     * pause, notification loss after Doze, BT stack wedge). The service would sit in
     * READY forever writing no data — exactly the field failure seen in participant
     * CSVs (a handful of rows, then silence with the hat still live). Detect it and
     * force a full disconnect/reconnect cycle, which re-runs MTU + CCCD + live-start.
     */
    private fun checkLiveStreamStall() {
        if (!isConnected) return
        val now = System.currentTimeMillis()
        val stalled = if (lastAcceptedFrameAtMs > 0L) {
            now - lastAcceptedFrameAtMs > LIVE_STALL_TIMEOUT_MS
        } else {
            lastStreamSetupAtMs > 0L && now - lastStreamSetupAtMs > NEVER_STREAMED_TIMEOUT_MS
        }
        if (!stalled) return
        Log.w(
            TAG,
            "Beanie live stream stalled (last frame ${if (lastAcceptedFrameAtMs > 0L) "${(now - lastAcceptedFrameAtMs) / 1000}s ago" else "never"}); forcing reconnect"
        )
        updateNotification("Beanie stream stalled - reconnecting...", force = true)
        disconnectGatt()
        broadcastStatus(STATUS_CONNECTING)
        scheduleReconnect(FAILURE_RECONNECT_DELAY_MS)
    }

    override fun onCreate() {
        super.onCreate()
        profile = UserProfile(this)
        dataManager = DataManager(this, profile)
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = manager?.adapter
        bleScanner = bluetoothAdapter?.bluetoothLeScanner
        targetAddress = profile.beanieDeviceAddress
        targetName = profile.beanieDeviceName
        refreshProfile()
        dataManager.initializeBeanieLogs()
        dataManager.startPeriodicFlush()
        activityEngine = ActivityEngine.getInstance(applicationContext)
        postureEngine = PostureEngine.getInstance(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // BLUETOOTH_CONNECT can be revoked between restarts (user action, or Android's
        // auto-revoke of unused permissions). Starting a FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
        // service without it throws SecurityException on Android 14+ — uncaught, that crashes
        // the app, and START_STICKY would just restart into the same crash.
        val hasBluetoothPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.BLUETOOTH_CONNECT) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!hasBluetoothPermission) {
            Log.w(TAG, "onStartCommand: BLUETOOTH_CONNECT missing — stopping service instead of crashing")
            stopSelf()
            return START_NOT_STICKY
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    Constants.NOTIFICATION_ID_BEANIE,
                    buildNotification("Searching for Beanie..."),
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                )
            } else {
                startForeground(
                    Constants.NOTIFICATION_ID_BEANIE,
                    buildNotification("Searching for Beanie...")
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "onStartCommand: startForeground failed — stopping service", e)
            stopSelf()
            return START_NOT_STICKY
        }
        connect()
        handler.removeCallbacks(heartbeatRunnable)
        handler.post(heartbeatRunnable)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        stopScan()
        disconnectGatt()
        publishStoppedSnapshot()
        dataManager.stopPeriodicFlush()
        dataManager.closeAll()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun refreshProfile() {
        packetParser = BeaniePacketParser(BeanieRegistry.profileForDevice(targetName))
    }

    private fun connect() {
        if (targetAddress.isBlank()) {
            updateNotification("No Beanie paired", force = true)
            broadcastStatus(STATUS_IDLE)
            return
        }

        val adapter = bluetoothAdapter ?: return
        if (!adapter.isEnabled) {
            scheduleReconnect()
            return
        }

        if (isConnected && bluetoothGatt != null) {
            updateNotification("Ready: Recording ${targetName.ifBlank { "Beanie" }}", force = true)
            broadcastStatus(STATUS_READY)
            return
        }

        if (!isConnected && bluetoothGatt != null) {
            broadcastStatus(STATUS_CONNECTING)
            if (autoConnectPending) {
                scheduleAutoReconnectScanFallback()
            }
            return
        }

        // CRITICAL: Clean up existing connection before starting a new one to prevent leaks
        disconnectGatt()

        if (targetAddress.isNotBlank()) {
            directConnectToSavedDevice(autoConnect = true)
        } else {
            scheduleReconnect()
        }
    }

    private fun startScan(): Boolean {
        val scanner = bleScanner ?: return false
        if (isScanning) return true
        isScanning = true
        handler.removeCallbacks(autoReconnectScanFallbackRunnable)
        
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        broadcastStatus(STATUS_SCANNING)
        updateNotification("Scanning for Beanie...", force = true)
        try {
            @Suppress("MissingPermission")
            scanner.startScan(null, settings, scanCallback)
            handler.removeCallbacks(scanTimeoutRunnable)
            handler.postDelayed(scanTimeoutRunnable, SCAN_WINDOW_MS)
            return true
        } catch (_: SecurityException) {
            isScanning = false
            return false
        }
    }

    private fun stopScan() {
        if (!isScanning) return
        isScanning = false
        handler.removeCallbacks(scanTimeoutRunnable)
        try {
            @Suppress("MissingPermission")
            bleScanner?.stopScan(scanCallback)
        } catch (_: Exception) {
        }
    }

    private fun resetActiveGattState(clearVitals: Boolean) {
        handler.removeCallbacks(connectingStallRunnable)
        handler.removeCallbacks(autoReconnectScanFallbackRunnable)
        handler.removeCallbacks(streamWarmupRunnable)
        handler.removeCallbacks(readPollRunnable)
        autoConnectPending = false
        readRequestInFlight = false
        activeDataCharacteristic = null
        activeDataProperties = 0
        activeCccdDescriptor = null
        activePushMode = null
        activeCommandCharacteristic = null
        commandWriteQueue.clear()
        commandWriteInFlight = false
        commandWriteRetryCount = 0
        lastCommandWritePayload = null
        liveStartRetryCount = 0
        lastStreamSetupAtMs = 0L
        receivedFrameThisConnection = false
        lastAcceptedFrameAtMs = 0L
        barcodePacketsRemaining = 0
        incomingStreamBuffer.clear()
        if (clearVitals) {
            lastTempSample = null
            batteryPct = null
        }
    }

    private fun disconnectGatt() {
        val gatt = bluetoothGatt
        bluetoothGatt = null
        isConnected = false
        resetActiveGattState(clearVitals = false)
        @Suppress("MissingPermission")
        gatt?.disconnect()
        @Suppress("MissingPermission")
        gatt?.close()
    }

    private fun ignoreStaleGattCallback(gatt: BluetoothGatt, callbackName: String): Boolean {
        if (bluetoothGatt === gatt) return false
        Log.w(TAG, "Ignoring $callbackName from stale GATT ${gatt.device?.address}")
        @Suppress("MissingPermission")
        gatt.close()
        return true
    }

    private fun scheduleConnectingWatchdog() {
        handler.removeCallbacks(connectingStallRunnable)
        handler.postDelayed(connectingStallRunnable, CONNECTING_STALL_TIMEOUT_MS)
    }

    private fun scheduleAutoReconnectScanFallback(delayMs: Long = AUTO_RECONNECT_SCAN_DELAY_MS) {
        handler.removeCallbacks(autoReconnectScanFallbackRunnable)
        handler.postDelayed(autoReconnectScanFallbackRunnable, delayMs)
    }

    private fun restartGatt(
        gatt: BluetoothGatt,
        reason: String,
        delayMs: Long = FAILURE_RECONNECT_DELAY_MS
    ) {
        Log.w(TAG, reason)
        if (bluetoothGatt === gatt) {
            bluetoothGatt = null
            isConnected = false
            resetActiveGattState(clearVitals = false)
        }
        @Suppress("MissingPermission")
        gatt.disconnect()
        @Suppress("MissingPermission")
        gatt.close()
        updateNotification("Beanie reconnecting...", force = true)
        broadcastStatus(STATUS_CONNECTING)
        scheduleReconnect(delayMs)
    }

    private fun scheduleStreamWarmupTimeout() {
        handler.removeCallbacks(streamWarmupRunnable)
        handler.postDelayed(streamWarmupRunnable, STREAM_WARMUP_TIMEOUT_MS)
    }

    private fun switchToReadPollingFallback(reason: String) {
        if (!supportsRead(activeDataProperties) || activeDataCharacteristic == null || bluetoothGatt == null) {
            Log.w(TAG, "$reason, but Beanie data characteristic is not readable")
            return
        }
        if (!useReadPollingFallback) {
            useReadPollingFallback = true
            Log.w(TAG, "$reason; switching Beanie to read polling fallback")
        }
        handler.removeCallbacks(streamWarmupRunnable)
        onNotifyEnabled()
        scheduleNextReadPoll(immediate = true)
    }

    private fun recoverSilentStream(reason: String) {
        if (activePushMode == PushMode.NOTIFY &&
            supportsIndicate(activeDataProperties) &&
            !preferIndicationFallback
        ) {
            val gatt = bluetoothGatt
            val characteristic = activeDataCharacteristic
            val descriptor = activeCccdDescriptor
            if (gatt != null && characteristic != null && descriptor != null) {
                preferIndicationFallback = true
                Log.w(TAG, "$reason; retrying Beanie stream with indications")
                enablePushMode(gatt, characteristic, descriptor, PushMode.INDICATE)
                return
            }
        }
        switchToReadPollingFallback(reason)
    }

    private fun enablePushMode(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        descriptor: BluetoothGattDescriptor,
        mode: PushMode
    ) {
        activePushMode = mode
        handler.removeCallbacks(streamWarmupRunnable)

        @Suppress("MissingPermission")
        val notificationRegistered = gatt.setCharacteristicNotification(characteristic, true)
        if (!notificationRegistered) {
            handlePushSetupFailure("BluetoothGatt rejected Beanie ${mode.name.lowercase(Locale.US)} registration")
            return
        }

        val cccdValue = cccdEnableValueFor(mode)
        Log.i(TAG, "Enabling Beanie ${mode.name.lowercase(Locale.US)} with properties=${characteristic.properties}")
        scheduleStreamWarmupTimeout()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                @Suppress("MissingPermission")
                val writeStatus = gatt.writeDescriptor(descriptor, cccdValue)
                if (writeStatus != BluetoothStatusCodes.SUCCESS) {
                    handler.removeCallbacks(streamWarmupRunnable)
                    handlePushSetupFailure(
                        "Beanie ${mode.name.lowercase(Locale.US)} CCCD write failed to start (status=$writeStatus)"
                    )
                }
            } else {
                @Suppress("DEPRECATION")
                descriptor.value = cccdValue
                @Suppress("MissingPermission", "DEPRECATION")
                val writeStarted = gatt.writeDescriptor(descriptor)
                if (!writeStarted) {
                    handler.removeCallbacks(streamWarmupRunnable)
                    handlePushSetupFailure(
                        "Beanie ${mode.name.lowercase(Locale.US)} CCCD write failed to start"
                    )
                }
            }
        } catch (_: SecurityException) {
            handler.removeCallbacks(streamWarmupRunnable)
            scheduleReconnect()
        }
    }

    private fun handlePushSetupFailure(reason: String) {
        handler.removeCallbacks(streamWarmupRunnable)
        recoverSilentStream(reason)
    }

    private fun scheduleNextReadPoll(immediate: Boolean = false) {
        handler.removeCallbacks(readPollRunnable)
        if (!useReadPollingFallback || !isConnected || activeDataCharacteristic == null) return
        if (immediate) {
            handler.post(readPollRunnable)
        } else {
            handler.postDelayed(readPollRunnable, READ_POLL_INTERVAL_MS)
        }
    }

    private fun pollDataCharacteristic() {
        val gatt = bluetoothGatt ?: return
        val characteristic = activeDataCharacteristic ?: return
        if (!supportsRead(activeDataProperties)) return
        try {
            @Suppress("MissingPermission", "DEPRECATION")
            val started = gatt.readCharacteristic(characteristic)
            if (started) {
                readRequestInFlight = true
            } else {
                Log.w(TAG, "Beanie read polling request was rejected by BluetoothGatt")
                scheduleNextReadPoll()
            }
        } catch (_: SecurityException) {
            scheduleReconnect()
        }
    }

    private fun startBeanieLiveStream() {
        if (activeCommandCharacteristic == null) {
            Log.w(TAG, "Beanie command characteristic unavailable; cannot send live-start commands")
            return
        }
        sendRtcAndResumeRecording()
    }

    private fun sendRtcAndResumeRecording() {
        enqueueCommandWrite(byteArrayOf(0xA4.toByte()))
        handler.postDelayed({ enqueueCommandWrite(buildSetTimePayload()) }, 300L)
        handler.postDelayed({ enqueueCommandWrite(byteArrayOf(0x04.toByte())) }, 600L)
    }

    private fun buildSetTimePayload(): ByteArray {
        val now = Calendar.getInstance()
        fun two(value: Int): String = String.format(Locale.US, "%02d", value)
        val ascii = (
            two(now.get(Calendar.MONTH) + 1) +
                two(now.get(Calendar.DAY_OF_MONTH)) +
                two(now.get(Calendar.YEAR) % 100) +
                two(now.get(Calendar.HOUR_OF_DAY)) +
                two(now.get(Calendar.MINUTE)) +
                two(now.get(Calendar.SECOND))
            ).toByteArray(Charsets.US_ASCII)
        return byteArrayOf(0x02.toByte()) + ascii
    }

    private fun enqueueCommandWrite(payload: ByteArray) {
        commandWriteQueue.add(payload)
        pumpCommandWriteQueue()
    }

    private fun pumpCommandWriteQueue() {
        if (commandWriteInFlight) return
        val gatt = bluetoothGatt ?: return
        val characteristic = activeCommandCharacteristic ?: return
        if (commandWriteQueue.isEmpty()) return

        val payload = commandWriteQueue.removeAt(0)
        lastCommandWritePayload = payload
        commandWriteInFlight = true

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                @Suppress("MissingPermission")
                val status = gatt.writeCharacteristic(
                    characteristic,
                    payload,
                    BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                )
                if (status != BluetoothStatusCodes.SUCCESS) {
                    commandWriteInFlight = false
                    commandWriteQueue.add(0, payload)
                    Log.w(TAG, "Beanie command write did not start status=$status")
                    handler.postDelayed({ pumpCommandWriteQueue() }, 250L)
                }
            } else {
                @Suppress("DEPRECATION")
                characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                @Suppress("DEPRECATION")
                characteristic.value = payload
                @Suppress("MissingPermission", "DEPRECATION")
                val started = gatt.writeCharacteristic(characteristic)
                if (!started) {
                    commandWriteInFlight = false
                    commandWriteQueue.add(0, payload)
                    Log.w(TAG, "Beanie command write did not start")
                    handler.postDelayed({ pumpCommandWriteQueue() }, 250L)
                }
            }
        } catch (_: SecurityException) {
            commandWriteInFlight = false
            commandWriteQueue.clear()
            scheduleReconnect()
        }
    }

    private fun directConnectToSavedDevice(autoConnect: Boolean = true) {
        val adapter = bluetoothAdapter ?: return
        if (targetAddress.isBlank()) {
            scheduleReconnect()
            return
        }
        try {
            val device = adapter.getRemoteDevice(targetAddress)
            updateNotification("Connecting to ${targetName.ifBlank { targetAddress }}...", force = true)
            broadcastStatus(STATUS_CONNECTING)
            Log.i(
                TAG,
                "Direct GATT connect fallback to $targetAddress (${targetName.ifBlank { "Beanie" }}) autoConnect=$autoConnect"
            )
            autoConnectPending = autoConnect
            // autoConnect must actually be passed through to connectGatt — it was
            // previously hardcoded to false here, making every reconnect a one-shot
            // ~30s attempt that race-fails whenever the hat is briefly out of range,
            // even though the whole autoConnectPending state machine around this call
            // assumes an OS-level background autoConnect. The reference Beanie app
            // (BleViewModel.performReconnect) documents this exact failure mode:
            // "autoConnect=false (old) was a one-shot attempt; if the beanie was out
            // of range overnight the reconnect loop would race-fail and stop trying."
            @Suppress("MissingPermission")
            bluetoothGatt = device.connectGatt(
                applicationContext,
                autoConnect,
                gattCallback,
                BluetoothDevice.TRANSPORT_LE
            )
            if (autoConnect) {
                scheduleAutoReconnectScanFallback()
            } else {
                scheduleConnectingWatchdog()
            }
        } catch (_: IllegalArgumentException) {
            scheduleReconnect()
        } catch (_: SecurityException) {
            scheduleReconnect()
        }
    }

    private fun scheduleReconnect(delayMs: Long = RECONNECT_DELAY_MS) {
        handler.removeCallbacks(reconnectRunnable)
        handler.postDelayed(reconnectRunnable, delayMs)
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            if (!BeanieDiscovery.matchesSavedDevice(result, targetAddress, targetName)) return

            val name = BeanieDiscovery.displayName(result).takeIf { it.isNotBlank() } ?: "Beanie (${device.address})"
            stopScan()
            targetAddress = device.address
            targetName = name
            profile.beanieDeviceAddress = targetAddress
            profile.beanieDeviceName = targetName
            refreshProfile()
            val pendingGatt = bluetoothGatt
            if (pendingGatt != null && !isConnected) {
                Log.i(TAG, "Closing pending Beanie autoConnect before foreground reconnect to ${device.address}")
                bluetoothGatt = null
                resetActiveGattState(clearVitals = false)
                @Suppress("MissingPermission")
                pendingGatt.disconnect()
                @Suppress("MissingPermission")
                pendingGatt.close()
            }
            Log.i(TAG, "Connecting to scanned Beanie ${device.address} ($name) with autoConnect=false")
            try {
                autoConnectPending = false
                @Suppress("MissingPermission")
                bluetoothGatt = device.connectGatt(
                    applicationContext,
                    false,
                    gattCallback,
                    BluetoothDevice.TRANSPORT_LE
                )
                scheduleConnectingWatchdog()
            } catch (_: SecurityException) {
                scheduleReconnect()
            }
        }

        override fun onScanFailed(errorCode: Int) {
            isScanning = false
            Log.w(TAG, "Beanie scan failed errorCode=$errorCode")
            if (autoConnectPending && bluetoothGatt != null) {
                updateNotification("Beanie scan failed - keeping reconnect active...", force = true)
                scheduleAutoReconnectScanFallback(AUTO_RECONNECT_SCAN_RETRY_MS)
            } else {
                scheduleReconnect()
            }
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (ignoreStaleGattCallback(gatt, "onConnectionStateChange")) return
            Log.i(TAG, "Gatt state change status=$status newState=$newState address=${gatt.device?.address}")
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    handler.removeCallbacks(connectingStallRunnable)
                    handler.removeCallbacks(autoReconnectScanFallbackRunnable)
                    stopScan()
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        restartGatt(gatt, "Beanie connected callback had status=$status; restarting connection")
                        return
                    }
                    isConnected = true
                    autoConnectPending = false
                    receivedFrameThisConnection = false
                    updateNotification("Connected to ${targetName.ifBlank { "Beanie" }} - discovering...", force = true)
                    broadcastStatus(STATUS_DISCOVERING)
                    handler.postDelayed({
                        @Suppress("MissingPermission")
                        val mtuStarted = gatt.requestMtu(517)
                        if (!mtuStarted) {
                            @Suppress("MissingPermission")
                            gatt.discoverServices()
                        }
                    }, 600L)
                }

                BluetoothProfile.STATE_DISCONNECTED -> {
                    handler.removeCallbacks(connectingStallRunnable)
                    handler.removeCallbacks(autoReconnectScanFallbackRunnable)
                    stopScan()
                    if (!receivedFrameThisConnection &&
                        supportsRead(activeDataProperties) &&
                        lastStreamSetupAtMs > 0L &&
                        System.currentTimeMillis() - lastStreamSetupAtMs <= STREAM_WARMUP_TIMEOUT_MS + 2_000L
                    ) {
                        useReadPollingFallback = true
                        Log.w(TAG, "Beanie disconnected before first sample; forcing read polling fallback on reconnect")
                    }
                    isConnected = false
                    bluetoothGatt = null
                    resetActiveGattState(clearVitals = true)
                    broadcastStatus(STATUS_DISCONNECTED)
                    updateNotification("Beanie disconnected - reconnecting...", force = true)
                    @Suppress("MissingPermission")
                    gatt.close()
                    scheduleReconnect()
                }
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            if (ignoreStaleGattCallback(gatt, "onMtuChanged")) return
            Log.i(TAG, "MTU changed mtu=$mtu status=$status")
            if (status != BluetoothGatt.GATT_SUCCESS) {
                restartGatt(gatt, "Beanie MTU negotiation failed status=$status; restarting connection")
                return
            }
            try {
                @Suppress("MissingPermission")
                gatt.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH)
            } catch (_: Exception) {
            }
            handler.postDelayed(
                {
                    if (bluetoothGatt !== gatt) return@postDelayed
                    try {
                        @Suppress("MissingPermission")
                        gatt.discoverServices()
                    } catch (_: SecurityException) {
                        restartGatt(gatt, "Beanie service discovery threw SecurityException; restarting connection")
                    }
                },
                250L
            )
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (ignoreStaleGattCallback(gatt, "onServicesDiscovered")) return
            Log.i(TAG, "Services discovered status=$status services=${gatt.services.size}")
            if (status != BluetoothGatt.GATT_SUCCESS) {
                restartGatt(gatt, "Beanie service discovery failed status=$status; restarting connection")
                return
            }

            val service = gatt.getService(BEANIE_SERVICE_UUID)
            if (service == null) {
                Log.e(TAG, "Beanie Service NOT FOUND. Available services:")
                gatt.services.forEach { Log.e(TAG, "  Service: ${it.uuid}") }
                restartGatt(gatt, "Beanie service UUID missing after discovery; restarting connection")
                return
            }

            val dataChar = service.getCharacteristic(DATA_UUID)
            val cmdChar = service.getCharacteristic(CMD_UUID)
            if (dataChar == null) {
                Log.e(TAG, "DATA_UUID characteristic NOT FOUND. Available in service:")
                service.characteristics.forEach { Log.e(TAG, "  Char: ${it.uuid}") }
                restartGatt(gatt, "Beanie data characteristic missing after discovery; restarting connection")
                return
            }
            if (cmdChar == null) {
                Log.w(TAG, "CMD_UUID characteristic not found; Beanie live-start commands unavailable")
            }

            activeDataCharacteristic = dataChar
            activeDataProperties = dataChar.properties
            activeCommandCharacteristic = cmdChar
            readRequestInFlight = false
            commandWriteInFlight = false
            commandWriteRetryCount = 0
            lastCommandWritePayload = null
            commandWriteQueue.clear()
            liveStartRetryCount = 0
            lastStreamSetupAtMs = System.currentTimeMillis()

            if (useReadPollingFallback && supportsRead(activeDataProperties)) {
                Log.w(TAG, "Using Beanie read polling fallback for properties=${dataChar.properties}")
                onNotifyEnabled()
                scheduleNextReadPoll(immediate = true)
                return
            }

            val pushMode = pushModeFor(dataChar.properties, preferIndicationFallback)
            if (pushMode == null) {
                if (supportsRead(activeDataProperties)) {
                    switchToReadPollingFallback("Beanie characteristic exposes no notify/indicate capability")
                } else {
                    Log.w(TAG, "Beanie characteristic has unsupported properties=${dataChar.properties}")
                    onNotifyEnabled()
                }
                return
            }

            val descriptor = dataChar.getDescriptor(CCCD_UUID) ?: run {
                Log.w(TAG, "Beanie data characteristic has no CCCD descriptor; waiting for direct reads")
                onNotifyEnabled()
                scheduleStreamWarmupTimeout()
                return
            }
            activeCccdDescriptor = descriptor
            enablePushMode(gatt, dataChar, descriptor, pushMode)
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int
        ) {
            if (ignoreStaleGattCallback(gatt, "onDescriptorWrite")) return
            Log.i(TAG, "Descriptor write status=$status uuid=${descriptor.uuid}")
            if (status != BluetoothGatt.GATT_SUCCESS) {
                handler.removeCallbacks(streamWarmupRunnable)
                recoverSilentStream("Beanie CCCD write completed with status=$status")
                return
            }
            onNotifyEnabled()
            startBeanieLiveStream()
            scheduleStreamWarmupTimeout()
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            if (ignoreStaleGattCallback(gatt, "onCharacteristicWrite")) return
            commandWriteInFlight = false
            if (status != BluetoothGatt.GATT_SUCCESS) {
                val payload = lastCommandWritePayload
                if (payload != null && commandWriteRetryCount < 2) {
                    commandWriteRetryCount++
                    commandWriteQueue.add(0, payload)
                    Log.w(TAG, "Beanie command write failed status=$status; retrying $commandWriteRetryCount/2")
                } else {
                    Log.e(TAG, "Beanie command write failed status=$status; giving up")
                    commandWriteRetryCount = 0
                }
            } else {
                commandWriteRetryCount = 0
            }
            pumpCommandWriteQueue()
        }

        @Deprecated("Deprecated in API 33")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int
        ) {
            if (ignoreStaleGattCallback(gatt, "onCharacteristicRead")) return
            @Suppress("DEPRECATION")
            handleCharacteristicRead(status, characteristic.value)
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int
        ) {
            if (ignoreStaleGattCallback(gatt, "onCharacteristicRead")) return
            handleCharacteristicRead(status, value)
        }

        @Deprecated("Deprecated in API 33")
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (ignoreStaleGattCallback(gatt, "onCharacteristicChanged")) return
            @Suppress("DEPRECATION")
            processIncoming(characteristic.value)
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            if (ignoreStaleGattCallback(gatt, "onCharacteristicChanged")) return
            processIncoming(value)
        }
    }

    private fun onNotifyEnabled() {
        scanFailCount = 0
        updateNotification("Ready: Recording ${targetName.ifBlank { "Beanie" }}", force = true)
        broadcastStatus(STATUS_READY)
    }

    private fun handleCharacteristicRead(status: Int, value: ByteArray) {
        readRequestInFlight = false
        if (status == BluetoothGatt.GATT_SUCCESS) {
            processIncoming(value)
        } else {
            Log.w(TAG, "Beanie characteristic read failed with status=$status")
        }
        if (useReadPollingFallback) {
            scheduleNextReadPoll()
        }
    }

    /**
     * Per-notification, shape-based packet dispatch (reference-app parity).
     *
     * The previous implementation pushed every notification into a rolling byte deque
     * and scanned byte-by-byte for tag bytes. That misframes any packet type this port
     * doesn't know — storage notifies (2B 0xA1), command responses (5B 0xA2/0xA3/0xA4),
     * barcode chunks after 0xB0 — because any 0xA6/0xA0 byte *inside* those packets gets
     * extracted as a "temperature"/"battery" frame. In the field this produced a constant
     * garbage row (inner 23.68 / outer 0.00 / tskin 87.62) written next to every real
     * sample, and bogus battery readings (100 → 0). The reference app (BleViewModel
     * processIncoming) instead matches each whole notification against exact known
     * shapes and drops everything else — mirrored here. The stream-reassembly buffer
     * is kept, but only for 0xAA55 IMU packets, which are the one packet type large
     * enough to straddle notification boundaries when MTU negotiation fails.
     */
    private fun processIncoming(data: ByteArray) {
        if (data.isEmpty()) return
        val now = System.currentTimeMillis()

        // Continuation bytes of a fragmented IMU packet already being reassembled —
        // firmware sends packets sequentially, so nothing else can interleave mid-packet.
        if (incomingStreamBuffer.isNotEmpty()) {
            handleFrames(BeaniePayloadDecoder.splitStream(incomingStreamBuffer, data), now)
            return
        }

        val lead = data[0].toInt() and 0xFF

        // STOP_ALL barcode stream suppression: [0xB0] then 7 × 4-byte barcode chunks.
        // Checked first — the chunks are arbitrary bytes and must never reach parsing.
        if (data.size == 1 && lead == 0xB0) {
            barcodePacketsRemaining = 7
            return
        }
        if (barcodePacketsRemaining > 0) {
            barcodePacketsRemaining--
            return
        }

        when {
            // Storage-percent notify — not used by this app, but must be consumed
            // so it can't be misparsed.
            data.size == 2 && lead == 0xA1 -> return

            // Command responses/echoes (RTC setup 0xA4, worn state 0xA2, 0xA3) — consume.
            data.size == 5 && (lead == 0xA2 || lead == 0xA3 || lead == 0xA4) -> return

            // Battery: exactly 3 bytes, tag 0xA0. Deliberately does NOT stamp
            // lastAcceptedFrameAtMs — battery notifies can keep ticking even when the
            // live-start never took and no temp/IMU is flowing, and the stall watchdog
            // must fire in exactly that situation.
            data.size == 3 && lead == 0xA0 -> {
                batteryPct = BeaniePacketParser.parseBatteryPercent(data)
                broadcastStatus(if (isConnected) STATUS_READY else STATUS_CONNECTING)
            }

            // Live temperature v2: exactly 5 bytes, tag 0xA6.
            data.size == 5 && lead == 0xA6 -> handleTemperatureFrame(data, now)

            // Legacy live temperature: exactly 4 bytes, no tag (parser validates plausibility).
            data.size == 4 -> handleTemperatureFrame(data, now)

            // IMU packets (legacy 182B or stream-typed 247B, both lead 0xAA 0x55). Routed
            // through the reassembly buffer so partial packets survive small-MTU links.
            lead == 0xAA && data.size >= 2 && (data[1].toInt() and 0xFF) == 0x55 ->
                handleFrames(BeaniePayloadDecoder.splitStream(incomingStreamBuffer, data), now)

            else -> Log.d(TAG, "Dropping unrecognized Beanie notification (${data.size} bytes, lead=0x%02X".format(lead) + ")")
        }
    }

    private fun handleFrames(frames: List<BeaniePayloadFrame>, now: Long) {
        frames.forEach { frame ->
            when (frame) {
                is BeaniePayloadFrame.Battery -> {
                    batteryPct = BeaniePacketParser.parseBatteryPercent(frame.bytes)
                    broadcastStatus(if (isConnected) STATUS_READY else STATUS_CONNECTING)
                }

                is BeaniePayloadFrame.Temperature -> handleTemperatureFrame(frame.bytes, now)

                is BeaniePayloadFrame.Imu -> handleImuFrame(frame.bytes, now)
            }
        }
    }

    private fun handleTemperatureFrame(data: ByteArray, timestampMs: Long) {
        val sample = packetParser.parseTemperaturePacket(data, timestampMs)
        if (sample == null) {
            val hex = data.joinToString("") { "%02X".format(it) }
            Log.w(TAG, "Dropped Beanie temp frame ($hex)")
            return
        }

        handler.removeCallbacks(streamWarmupRunnable)
        receivedFrameThisConnection = true
        lastAcceptedFrameAtMs = timestampMs
        lastTempSample = sample
        val beanieProfile = BeanieRegistry.profileForDevice(targetName)
        val profileName = beanieProfile.name

        // TskinSynthesizer: smoothed/denoised tSkin fed to the ML model only.
        // dt measured from actual wall-clock gap between temperature packets so
        // the filter's rate limiters/EMA behave correctly regardless of the
        // firmware's exact packet cadence.
        val dtSec = if (lastTskinUpdateAtMs > 0L) {
            (timestampMs - lastTskinUpdateAtMs).coerceAtLeast(1L) / 1000.0
        } else {
            1.0
        }
        lastTskinUpdateAtMs = timestampMs
        val tskinOut = tskinSynthesizer.update(
            time = Date(timestampMs),
            innerC = sample.innerC,
            outerC = sample.outerC,
            dt = dtSec,
            c1 = beanieProfile.c1
        )

        val row = buildString {
            append(sample.timestampMs).append(',')
            append(csvSafe(targetName)).append(',')
            append(targetAddress).append(',')
            append(csvSafe(profileName)).append(',')
            append(formatDouble(sample.innerC)).append(',')
            append(formatDouble(sample.outerC)).append(',')
            append(formatDouble(sample.tskinC)).append(',')
            append(formatDouble(sample.heatFluxCalPerSec)).append(',')
            append(batteryPct?.toString() ?: "").append(',')
            if (activityEngine.isReady.value) {
                append(activityEngine.currentActivity.value).append(',')
                append(formatDouble(activityEngine.confidence.value))
            } else {
                append(',').append("")
            }
        }
        dataManager.writeBeanieTemperatureData(row)

        // Trigger activity inference with accumulated IMU + temperature data
        if (imuRingBuffer.size >= 250) {
            val imuMatrix = imuRingBuffer.toTypedArray()
            val postureSeries = postureEngine.getPostureSeries(250)
            val windowEndMs = timestampMs
            // Timestamp of the oldest sample in the *last 250* rows actually fed to the
            // model — not the oldest row in the full 1001-row ring buffer.
            val windowStartMs = imuTimestamps.toList().takeLast(minOf(250, imuTimestamps.size))
                .firstOrNull() ?: windowEndMs
            activityEngine.startInference(
                imuMatrix = imuMatrix,
                tSkin = tskinOut.synthC,
                outerC = sample.outerC,
                heatFluxCalPerSec = sample.heatFluxCalPerSec,
                postureSeries = postureSeries,
                windowStartMs = windowStartMs,
                windowEndMs = windowEndMs
            )
        }

        broadcastStatus(STATUS_READY)
        updateNotification(
            "Skin ${formatDouble(sample.tskinC)}C | In ${formatDouble(sample.innerC)} / Out ${formatDouble(sample.outerC)}",
            force = true
        )
    }

    private fun handleImuFrame(data: ByteArray, timestampMs: Long) {
        val samples = packetParser.parseImuPacket(data, timestampMs)
        if (samples.isEmpty()) {
            Log.w(TAG, "Dropped Beanie IMU frame (${data.size} bytes)")
            return
        }
        handler.removeCallbacks(streamWarmupRunnable)
        receivedFrameThisConnection = true
        lastAcceptedFrameAtMs = timestampMs
        val rows = samples.map { sample ->
            buildString {
                append(sample.timestampMs).append(',')
                append(csvSafe(targetName)).append(',')
                append(targetAddress).append(',')
                append(sample.axRaw).append(',')
                append(sample.ayRaw).append(',')
                append(sample.azRaw).append(',')
                append(sample.gxRaw).append(',')
                append(sample.gyRaw).append(',')
                append(sample.gzRaw).append(',')
                append(formatDouble(sample.axG)).append(',')
                append(formatDouble(sample.ayG)).append(',')
                append(formatDouble(sample.azG)).append(',')
                append(formatDouble(sample.accelMagG)).append(',')
                append(formatDouble(sample.gxDps)).append(',')
                append(formatDouble(sample.gyDps)).append(',')
                append(formatDouble(sample.gzDps)).append(',')
                append(formatDouble(sample.gyroMagDps))
            }
        }
        dataManager.writeBeanieImuData(rows)

        // Feed samples to inference engines. PostureEngine.process() takes the whole
        // batch (it does its own raw→scaled conversion internally, same as it does for
        // every other Beanie packet) — there is no feedScaledImuSample() method on
        // PostureEngine, so calling it per-sample here was a compile error.
        postureEngine.process(samples)
        for (sample in samples) {
            val row = floatArrayOf(
                sample.axG.toFloat(),
                sample.ayG.toFloat(),
                sample.azG.toFloat(),
                sample.accelMagG.toFloat(),
                sample.gxDps.toFloat(),
                sample.gyDps.toFloat(),
                sample.gzDps.toFloat()
            )
            if (imuRingBuffer.size >= 1001) imuRingBuffer.removeFirst()
            imuRingBuffer.addLast(row)
            if (imuTimestamps.size >= 1001) imuTimestamps.removeFirst()
            imuTimestamps.addLast(sample.timestampMs)
        }
    }

    private fun broadcastStatus(status: String) {
        val temp = freshTempSample().takeIf { isConnected }
        val snapshot = currentSnapshot(status, temp)
        if (snapshot == lastBroadcastSnapshot) return
        lastBroadcastSnapshot = snapshot
        BeanieStatusStore.save(
            this,
            snapshot
        )
        val intent = Intent(ACTION_BEANIE_UPDATE).apply {
            setPackage(packageName)
            putExtra(EXTRA_CONNECTED, snapshot.connected)
            putExtra(EXTRA_STATUS, snapshot.status)
            putExtra(EXTRA_DEVICE_NAME, snapshot.deviceName)
            if (temp != null) {
                putExtra(EXTRA_INNER_C, temp.innerC)
                putExtra(EXTRA_OUTER_C, temp.outerC)
                putExtra(EXTRA_TSKIN_C, snapshot.tskinC)
                putExtra(EXTRA_HEAT_FLUX, snapshot.heatFluxCalPerSec)
            }
            snapshot.batteryPct?.let { putExtra(EXTRA_BATTERY_PCT, it) }
            if (activityEngine.isReady.value) {
                putExtra(EXTRA_ACTIVITY_LABEL, activityEngine.currentActivity.value)
                putExtra(EXTRA_ACTIVITY_CONFIDENCE, activityEngine.confidence.value.toFloat())
            }
        }
        sendBroadcast(intent)
    }

    private fun updateNotification(text: String, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force) {
            if (text == lastNotificationText) return
            if (now - lastNotificationAtMs < LIVE_NOTIFICATION_MIN_INTERVAL_MS) return
        }
        lastNotificationText = text
        lastNotificationAtMs = now
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        notificationManager.notify(Constants.NOTIFICATION_ID_BEANIE, buildNotification(text))
    }

    private fun currentSnapshot(
        status: String,
        temp: BeaniePacketParser.TemperatureSample? = freshTempSample()
    ): BeanieStatusSnapshot {
        return BeanieStatusSnapshot(
            connected = isConnected,
            status = status,
            deviceName = targetName.trim(),
            tskinC = roundForUi(temp?.tskinC ?: Double.NaN),
            heatFluxCalPerSec = roundForUi(temp?.heatFluxCalPerSec ?: Double.NaN),
            batteryPct = batteryPct,
            activityLabel = activityEngine.currentActivity.value.takeIf {
                activityEngine.isReady.value && it.isNotEmpty()
            },
            activityConfidence = activityEngine.confidence.value.takeIf {
                activityEngine.isReady.value && activityEngine.currentActivity.value.isNotEmpty()
            }
        )
    }

    private fun freshTempSample(nowMs: Long = System.currentTimeMillis()): BeaniePacketParser.TemperatureSample? {
        return lastTempSample?.takeIf { nowMs - it.timestampMs <= TEMP_SAMPLE_STALE_MS }
    }

    private fun publishStoppedSnapshot() {
        lastTempSample = null
        batteryPct = null
        isConnected = false
        val snapshot = BeanieStatusSnapshot(
            connected = false,
            status = STATUS_IDLE,
            deviceName = targetName.trim(),
            tskinC = Double.NaN,
            heatFluxCalPerSec = Double.NaN,
            batteryPct = null
        )
        lastBroadcastSnapshot = snapshot
        BeanieStatusStore.save(this, snapshot)
        sendBroadcast(
            Intent(ACTION_BEANIE_UPDATE).apply {
                setPackage(packageName)
                putExtra(EXTRA_CONNECTED, false)
                putExtra(EXTRA_STATUS, STATUS_IDLE)
                putExtra(EXTRA_DEVICE_NAME, snapshot.deviceName)
            }
        )
    }

    private fun buildNotification(contentText: String): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, Constants.CHANNEL_BEANIE)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Beanie monitor")
            .setContentText(contentText)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun formatDouble(value: Double): String = String.format(Locale.US, "%.2f", value)

    private fun csvSafe(value: String): String = value.replace(",", " ").trim()

    private fun roundForUi(value: Double): Double {
        if (!value.isFinite()) return Double.NaN
        return kotlin.math.round(value * 100.0) / 100.0
    }
}
