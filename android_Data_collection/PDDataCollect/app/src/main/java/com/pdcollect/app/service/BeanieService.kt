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
import java.util.Locale
import java.util.UUID

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

        const val STATUS_IDLE = "IDLE"
        const val STATUS_SCANNING = "SCANNING"
        const val STATUS_CONNECTING = "CONNECTING"
        const val STATUS_DISCOVERING = "DISCOVERING"
        const val STATUS_READY = "READY"
        const val STATUS_DISCONNECTED = "DISCONNECTED"

        fun start(context: Context) {
            // Feature disabled per request
            return
            /*
            ContextCompat.startForegroundService(
                context,
                Intent(context, BeanieService::class.java)
            )
            */
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
    private val incomingStreamBuffer = ArrayDeque<Byte>()
    private val commandWriteQueue = mutableListOf<ByteArray>()
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
            when {
                isConnected -> broadcastStatus(STATUS_READY)
                targetAddress.isNotBlank() -> broadcastStatus(STATUS_CONNECTING)
                else -> broadcastStatus(STATUS_IDLE)
            }
            handler.postDelayed(this, 15_000L)
        }
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
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
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
                    @Suppress("MissingPermission")
                    val mtuStarted = gatt.requestMtu(517)
                    if (!mtuStarted) {
                        @Suppress("MissingPermission")
                        gatt.discoverServices()
                    }
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

    private fun processIncoming(data: ByteArray) {
        if (data.isEmpty()) return
        val now = System.currentTimeMillis()
        val frames = BeaniePayloadDecoder.splitStream(incomingStreamBuffer, data)
        if (frames.isEmpty()) {
            Log.d(TAG, "Ignoring unrecognized Beanie payload (${data.size} bytes)")
            return
        }

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
        lastTempSample = sample
        val profileName = BeanieRegistry.profileForDevice(targetName).name
        val row = buildString {
            append(sample.timestampMs).append(',')
            append(csvSafe(targetName)).append(',')
            append(targetAddress).append(',')
            append(csvSafe(profileName)).append(',')
            append(formatDouble(sample.innerC)).append(',')
            append(formatDouble(sample.outerC)).append(',')
            append(formatDouble(sample.tskinC)).append(',')
            append(formatDouble(sample.heatFluxCalPerSec)).append(',')
            append(batteryPct?.toString() ?: "")
        }
        dataManager.writeBeanieTemperatureData(row)
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
            batteryPct = batteryPct
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
