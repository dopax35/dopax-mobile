package com.pdcollect.app.service

import android.Manifest
import android.app.Notification
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
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

class PDCollectService : LifecycleService(), SensorEventListener {

    private lateinit var sensorManager: SensorManager
    private lateinit var dataManager: DataManager
    private lateinit var profile: UserProfile
    private val sensorBuffer = mutableListOf<String>()
    private val handler = Handler(Looper.getMainLooper())

    private var lastAccel = FloatArray(3)
    private var lastGyro = FloatArray(3)
    private var lastMag = FloatArray(3)
    private var bootToEpochOffsetNs = 0L
    private var isServiceActive = false
    private var shellyBleScanner: ShellyBleScanner? = null

    private val flushRunnable = object : Runnable {
        override fun run() {
            flushBuffer()
            handler.postDelayed(this, Constants.SENSOR_BUFFER_FLUSH_INTERVAL_MS)
        }
    }

    private val shellyRestartRunnable = object : Runnable {
        override fun run() {
            // Android limits continuous BLE scans to 30 mins. Restart it periodically.
            // Guarded: an uncaught exception here (e.g. BLE permission revoked, adapter
            // error) would crash the whole app from this Handler's callback.
            try {
                shellyBleScanner?.stopScanning()
            } catch (e: Exception) {
                android.util.Log.e(TAG, "shellyRestartRunnable: stopScanning failed", e)
            }
            handler.postDelayed({
                if (isServiceActive) {
                    try {
                        shellyBleScanner?.startPassive()
                    } catch (e: Exception) {
                        android.util.Log.e(TAG, "shellyRestartRunnable: startPassive failed", e)
                    }
                }
            }, 2000)
            handler.postDelayed(this, 15 * 60 * 1000L) // 15 mins
        }
    }

    override fun onCreate() {
        super.onCreate()
        profile = UserProfile(this)
        dataManager = DataManager(this, profile)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        bootToEpochOffsetNs = System.currentTimeMillis() * 1_000_000L - SystemClock.elapsedRealtimeNanos()

        if (Constants.SHELLY_BLE_ENABLED) {
            shellyBleScanner = ShellyBleScanner(this, profile, dataManager)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        isServiceActive = true

        updateForegroundNotification()

        registerSensors()
        handler.removeCallbacks(flushRunnable)
        handler.postDelayed(flushRunnable, Constants.SENSOR_BUFFER_FLUSH_INTERVAL_MS)
        dataManager.startPeriodicFlush()
        // Pre-create ALL expected CSV files with their headers for today's date so
        // no files are ever missing from a day's directory in the research data.
        dataManager.initializeAllDailyLogs()

        if (Constants.SHELLY_BLE_ENABLED) {
            try {
                shellyBleScanner?.startPassive()
            } catch (e: Exception) {
                android.util.Log.e(TAG, "onStartCommand: shelly startPassive failed", e)
            }
            handler.removeCallbacks(shellyRestartRunnable)
            handler.postDelayed(shellyRestartRunnable, 15 * 60 * 1000L) // 15 mins
        }

        return START_STICKY
    }

    private fun registerSensors() {
        val accel = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        val gyro = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
        val mag = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)

        accel?.let {
            sensorManager.registerListener(
                this,
                it,
                Constants.SENSOR_DELAY_US,
                Constants.SENSOR_BATCH_LATENCY_US
            )
        }
        gyro?.let {
            sensorManager.registerListener(
                this,
                it,
                Constants.SENSOR_DELAY_US,
                Constants.SENSOR_BATCH_LATENCY_US
            )
        }
        mag?.let {
            sensorManager.registerListener(
                this,
                it,
                Constants.SENSOR_DELAY_US,
                Constants.SENSOR_BATCH_LATENCY_US
            )
        }
    }

    private fun updateForegroundNotification() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    Constants.NOTIFICATION_ID_SENSOR,
                    buildNotification(),
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(Constants.NOTIFICATION_ID_SENSOR, buildNotification())
            }
        } catch (e: SecurityException) {
            android.util.Log.e(TAG, "FGS specialUse registration security exception: ${e.message}")
        }
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent, PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, Constants.CHANNEL_SENSOR)
            .setContentTitle("PD Data Collection")
            .setContentText("Collecting passive sensor data...")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> {
                lastAccel = event.values.copyOf()
                bufferReading(event.timestamp)
            }
            Sensor.TYPE_GYROSCOPE -> {
                lastGyro = event.values.copyOf()
            }
            Sensor.TYPE_MAGNETIC_FIELD -> {
                lastMag = event.values.copyOf()
            }
        }
    }

    private fun bufferReading(timestampNs: Long) {
        val unixNs = timestampNs + bootToEpochOffsetNs
        val row = buildString(128) {
            append(unixNs).append(',')
            append(lastAccel[0]).append(',')
            append(lastAccel[1]).append(',')
            append(lastAccel[2]).append(',')
            append(lastGyro[0]).append(',')
            append(lastGyro[1]).append(',')
            append(lastGyro[2]).append(',')
            append(lastMag[0]).append(',')
            append(lastMag[1]).append(',')
            append(lastMag[2])
        }

        synchronized(sensorBuffer) {
            sensorBuffer.add(row)
            if (sensorBuffer.size >= Constants.SENSOR_BUFFER_MAX_SIZE) {
                flushBuffer()
            }
        }
    }

    private fun flushBuffer() {
        val rows: List<String>
        synchronized(sensorBuffer) {
            if (sensorBuffer.isEmpty()) return
            rows = sensorBuffer.toList()
            sensorBuffer.clear()
        }
        dataManager.writeSensorData(rows)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun onBind(intent: Intent): IBinder? {
        super.onBind(intent)
        return null
    }

    override fun onDestroy() {
        isServiceActive = false
        shellyBleScanner?.stopScanning()
        handler.removeCallbacks(flushRunnable)
        handler.removeCallbacks(shellyRestartRunnable)
        sensorManager.unregisterListener(this)
        flushBuffer()
        dataManager.stopPeriodicFlush()
        dataManager.closeAll()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "PDCollectService"

        fun start(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, PDCollectService::class.java)
            )
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, PDCollectService::class.java))
        }
    }
}
