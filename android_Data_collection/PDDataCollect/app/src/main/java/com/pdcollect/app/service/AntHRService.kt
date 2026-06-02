package com.pdcollect.app.service

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.*
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import androidx.core.app.NotificationCompat
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.ui.MainActivity
import com.pdcollect.app.util.Constants
import java.util.UUID

class AntHRService : Service() {

    companion object {
        private const val TAG = "AntHRService"

        // Standard BLE Heart Rate Service & Characteristic UUIDs (Bluetooth SIG)
        val HR_SERVICE_UUID: UUID = UUID.fromString("0000180d-0000-1000-8000-00805f9b34fb")
        val HR_MEASUREMENT_UUID: UUID = UUID.fromString("00002a37-0000-1000-8000-00805f9b34fb")
        val CLIENT_CHARACTERISTIC_CONFIG_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        private const val RECONNECT_DELAY_MS = 5000L

        // Intent extras for broadcasting current HR to UI
        const val ACTION_HR_UPDATE = "com.pdcollect.app.HR_UPDATE"
        const val EXTRA_BPM = "extra_bpm"
        const val EXTRA_HRV = "extra_hrv"
        const val EXTRA_DEVICE_NAME = "extra_device_name"
        const val EXTRA_CONNECTED = "extra_connected"
        const val EXTRA_STATUS = "extra_status"

        // Status values
        const val STATUS_IDLE = "IDLE"
        const val STATUS_SCANNING = "SCANNING"
        const val STATUS_CONNECTING = "CONNECTING"
        const val STATUS_DISCOVERING = "DISCOVERING"
        const val STATUS_READY = "READY"
        const val STATUS_DISCONNECTED = "DISCONNECTED"

        fun start(context: Context) {
            context.startForegroundService(Intent(context, AntHRService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, AntHRService::class.java))
        }
    }

    private lateinit var profile: UserProfile
    private lateinit var dataManager: DataManager
    private val handler = Handler(Looper.getMainLooper())

    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bleScanner: BluetoothLeScanner? = null
    private var bluetoothGatt: BluetoothGatt? = null

    private var isScanning = false
    private var targetAddress: String = ""
    private var targetName: String = ""
    private var lastBpm = 0
    private var isConnected = false

    // Sliding window for HRV (60 seconds)
    private val rrIntervalWindow = mutableListOf<Pair<Long, Int>>() // Pair(timestamp, rr_ms)
    private var lastHrvRmssd = 0f

    private val heartbeatRunnable = object : Runnable {
        override fun run() {
            if (isConnected) {
                broadcastStatus(STATUS_READY)
            } else if (targetAddress.isNotEmpty()) {
                broadcastStatus(STATUS_CONNECTING)
            }
            handler.postDelayed(this, 5000) // Periodic UI sync
        }
    }

    // ─── Lifecycle ──────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        profile = UserProfile(this)
        dataManager = DataManager(this, profile)
        bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter
        bleScanner = bluetoothAdapter?.bluetoothLeScanner
        targetAddress = profile.hrDeviceAddress
        targetName = profile.hrDeviceName
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                Constants.NOTIFICATION_ID_HR,
                buildNotification("Searching for HR monitor…"),
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(Constants.NOTIFICATION_ID_HR, buildNotification("Searching for HR monitor…"))
        }
        connect()
        handler.post(heartbeatRunnable)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        handler.removeCallbacks(heartbeatRunnable)
        stopScan()
        disconnectGatt()

        val timestamp = System.currentTimeMillis()
        dataManager.writeHeartRateData("$timestamp,0,SERVICE_STOP,$targetAddress,$targetName")

        dataManager.closeAll()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ─── Connection Logic ────────────────────────────────────────────────────────

    private fun connect() {
        if (targetAddress.isBlank()) {
            // No device paired yet — nothing to do, wait for device picker to pair one
            Log.d(TAG, "No HR device address saved. Waiting for pairing.")
            updateNotification("No HR device paired. Open app to connect.")
            return
        }

        val adapter = bluetoothAdapter ?: return
        if (!adapter.isEnabled) {
            Log.d(TAG, "Bluetooth disabled, will retry in ${RECONNECT_DELAY_MS}ms")
            scheduleReconnect()
            return
        }

        // Try direct connect if we already know the address
        try {
            val device = adapter.getRemoteDevice(targetAddress)
            Log.d(TAG, "Connecting to $targetAddress (${targetName})…")
            updateNotification("Connecting to ${targetName.ifBlank { targetAddress }}…")
            @Suppress("MissingPermission")
            bluetoothGatt = device.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        } catch (e: IllegalArgumentException) {
            Log.e(TAG, "Invalid device address, starting scan instead", e)
            startScan()
        }
    }

    private fun startScan() {
        val scanner = bleScanner ?: return
        if (isScanning) return
        isScanning = true

        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(HR_SERVICE_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_POWER)
            .build()

        Log.d(TAG, "Starting BLE scan for HR devices…")
        updateNotification("Scanning for HR devices…")
        broadcastStatus(STATUS_SCANNING)
        @Suppress("MissingPermission")
        scanner.startScan(listOf(filter), settings, scanCallback)
    }

    private fun stopScan() {
        if (!isScanning) return
        isScanning = false
        try {
            @Suppress("MissingPermission")
            bleScanner?.stopScan(scanCallback)
        } catch (_: Exception) {}
    }

    private fun disconnectGatt() {
        @Suppress("MissingPermission")
        bluetoothGatt?.disconnect()
        @Suppress("MissingPermission")
        bluetoothGatt?.close()
        bluetoothGatt = null
    }

    private fun scheduleReconnect() {
        handler.postDelayed({ connect() }, RECONNECT_DELAY_MS)
    }

    // ─── BLE Scan Callback ───────────────────────────────────────────────────────

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            @Suppress("MissingPermission")
            val name = result.device.name ?: "Unknown HR Device"
            Log.d(TAG, "Scan found: ${device.address} / $name")

            // If we have a stored address, only connect to that one.
            // Otherwise accept the first HR device found (shouldn't normally happen post-pairing).
            if (targetAddress.isBlank() || device.address == targetAddress) {
                stopScan()
                targetAddress = device.address
                targetName = name
                profile.hrDeviceAddress = targetAddress
                profile.hrDeviceName = name
                updateNotification("Connecting to $name…")
                @Suppress("MissingPermission")
                bluetoothGatt = device.connectGatt(applicationContext, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
            }
        }

        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "BLE scan failed: $errorCode")
            isScanning = false
            scheduleReconnect()
        }
    }

    // ─── GATT Callback ───────────────────────────────────────────────────────────

    private val gattCallback = object : BluetoothGattCallback() {

        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    Log.d(TAG, "GATT connected, discovering services…")
                    isConnected = true
                    updateNotification("Connected to $targetName — discovering…")
                    broadcastStatus(STATUS_DISCOVERING)
                    @Suppress("MissingPermission")
                    gatt.discoverServices()
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    Log.d(TAG, "GATT disconnected (status=$status), reconnecting…")
                    isConnected = false
                    lastBpm = 0
                    broadcastUpdate(connected = false, bpm = 0)
                    updateNotification("Disconnected — reconnecting…")
                    @Suppress("MissingPermission")
                    gatt.close()
                    bluetoothGatt = null
                    scheduleReconnect()
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                Log.e(TAG, "Service discovery failed: $status")
                return
            }
            val hrService = gatt.getService(HR_SERVICE_UUID)
            val hrChar = hrService?.getCharacteristic(HR_MEASUREMENT_UUID)

            if (hrChar == null) {
                Log.e(TAG, "Heart Rate Measurement characteristic not found!")
                return
            }

            @Suppress("MissingPermission")
            gatt.setCharacteristicNotification(hrChar, true)

            // Write to CCCD (descriptor) to enable remote notifications
            val descriptor = hrChar.getDescriptor(CLIENT_CHARACTERISTIC_CONFIG_UUID)
            if (descriptor != null) {
                descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                @Suppress("MissingPermission")
                gatt.writeDescriptor(descriptor)
                Log.d(TAG, "Notifications enabled on HR characteristic")
                updateNotification("Ready: Recording $targetName")
                broadcastStatus(STATUS_READY)
                
                // Log ready state
                val timestamp = System.currentTimeMillis()
                dataManager.writeHeartRateData("$timestamp,0,HEARTBEAT_READY,$targetAddress,$targetName")
            }
        }

        @Deprecated("Deprecated in API 33", ReplaceWith("onCharacteristicChanged(gatt, characteristic, value)"))
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            @Suppress("DEPRECATION")
            parseHrMeasurement(characteristic.value)
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            parseHrMeasurement(value)
        }
    }

    // ─── HR Data Parsing ─────────────────────────────────────────────────────────

    /**
     * Parse Heart Rate Measurement characteristic per Bluetooth HRP spec:
     *   Byte 0: Flags
     *     bit 0 → 0 = HR is uint8 at byte 1, 1 = HR is uint16 at bytes 1-2
     *     bit 4 → RR-interval(s) present
     *   Bytes 1+ : BPM (uint8 or uint16)
     *   Remaining: RR intervals (uint16 each, in units of 1/1024 s)
     */
    private fun parseHrMeasurement(value: ByteArray) {
        if (value.isEmpty()) return

        val flags = value[0].toInt() and 0xFF
        val hrFormat16bit = flags and 0x01 != 0
        val rrPresent = flags and 0x10 != 0

        val bpm: Int
        var rrOffset: Int

        if (hrFormat16bit) {
            if (value.size < 3) return
            bpm = (value[1].toInt() and 0xFF) or ((value[2].toInt() and 0xFF) shl 8)
            rrOffset = 3
        } else {
            if (value.size < 2) return
            bpm = value[1].toInt() and 0xFF
            rrOffset = 2
        }

        val rrIntervals = mutableListOf<Int>()
        if (rrPresent) {
            while (rrOffset + 1 < value.size) {
                val rr = (value[rrOffset].toInt() and 0xFF) or ((value[rrOffset + 1].toInt() and 0xFF) shl 8)
                // RR value is in 1/1024 seconds, convert to ms
                rrIntervals.add((rr * 1000) / 1024)
                rrOffset += 2
            }
        }

        lastBpm = bpm
        val timestamp = System.currentTimeMillis()
        
        // Update 60s sliding window for HRV
        if (rrIntervals.isNotEmpty()) {
            rrIntervals.forEach { rr ->
                rrIntervalWindow.add(timestamp to rr)
            }
        }
        // Remove intervals older than 60s
        val windowLimit = timestamp - 60000
        rrIntervalWindow.removeAll { it.first < windowLimit }
        
        // Calculate RMSSD from the current window
        lastHrvRmssd = calculateRmssd(rrIntervalWindow.map { it.second })

        val rrStr = if (rrIntervals.isNotEmpty()) rrIntervals.joinToString("|") else ""

        val row = "$timestamp,$bpm,$rrStr,$targetAddress,$targetName"
        dataManager.writeHeartRateData(row)
        broadcastUpdate(connected = true, bpm = bpm, hrv = lastHrvRmssd)

        Log.v(TAG, "HR: $bpm bpm | HRV (60s RMSSD): ${lastHrvRmssd.toInt()} ms | RR: $rrStr ms")
    }

    private fun calculateRmssd(rrIntervals: List<Int>): Float {
        if (rrIntervals.size < 2) return 0f
        var sumSqDiff = 0.0
        for (i in 1 until rrIntervals.size) {
            val diff = (rrIntervals[i] - rrIntervals[i - 1]).toDouble()
            sumSqDiff += diff * diff
        }
        return kotlin.math.sqrt(sumSqDiff / (rrIntervals.size - 1)).toFloat()
    }

    // ─── Notification & Broadcast ────────────────────────────────────────────────

    private fun broadcastUpdate(connected: Boolean, bpm: Int, hrv: Float = 0f) {
        val intent = Intent(ACTION_HR_UPDATE).apply {
            setPackage(packageName)
            putExtra(EXTRA_CONNECTED, connected)
            putExtra(EXTRA_BPM, bpm)
            putExtra(EXTRA_HRV, hrv)
            putExtra(EXTRA_DEVICE_NAME, targetName)
        }
        sendBroadcast(intent)
    }

    private fun broadcastStatus(status: String) {
        val intent = Intent(ACTION_HR_UPDATE).apply {
            setPackage(packageName)
            putExtra(EXTRA_CONNECTED, isConnected)
            putExtra(EXTRA_STATUS, status)
            putExtra(EXTRA_DEVICE_NAME, targetName)
            if (status == STATUS_READY) {
                putExtra(EXTRA_BPM, lastBpm)
                putExtra(EXTRA_HRV, lastHrvRmssd)
            }
        }
        sendBroadcast(intent)
    }

    private fun updateNotification(text: String) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        notificationManager.notify(Constants.NOTIFICATION_ID_HR, buildNotification(text))
    }

    private fun buildNotification(contentText: String = "Heart rate monitor active"): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, Constants.CHANNEL_HR)
            .setContentTitle("❤️ HR Monitor")
            .setContentText(contentText)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
}
