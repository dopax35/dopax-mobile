package com.pdcollect.app.service

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile

@SuppressLint("MissingPermission")
class ShellyBleScanner(
    private val context: Context,
    private val profile: UserProfile,
    private val dataManager: DataManager?
) {
    private val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    private val bluetoothAdapter = bluetoothManager?.adapter
    private val bleScanner: BluetoothLeScanner? = bluetoothAdapter?.bluetoothLeScanner
    private val mainHandler = Handler(Looper.getMainLooper())

    private var isScanning = false
    private var pairingCallback: ((String) -> Unit)? = null
    
    private var lastMedicationLogTime = 0L

    // BTHome UUID
    private val BTHOME_SERVICE_UUID = ParcelUuid.fromString("0000fcd2-0000-1000-8000-00805f9b34fb")

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            super.onScanResult(callbackType, result)
            result ?: return

            val scanRecord = result.scanRecord ?: return
            val serviceData = scanRecord.getServiceData(BTHOME_SERVICE_UUID) ?: return

            val macAddress = result.device.address

            // Pairing Mode: Pair immediately with any device broadcasting BTHome
            if (pairingCallback != null) {
                pairingCallback?.invoke(macAddress)
                stopScanning()
                return
            }

            val isActionTriggered = parseBTHomeAction(serviceData)
            
            if (!isActionTriggered) return

            // Passive Monitoring Mode
            val savedMac = profile.shellyMacAddress
            if (savedMac.isNotEmpty() && !macAddress.equals(savedMac, ignoreCase = true)) {
                return // Not the paired device
            }

            // Debounce: 30 seconds (30,000 ms) to allow for frequent testing but prevent double-logs
            val now = System.currentTimeMillis()
            if (now - lastMedicationLogTime > 30_000) {
                lastMedicationLogTime = now
                Log.d(TAG, "Pillbox opened! Logging medication.")
                
                // Format: timestamp_ms,taken_ms,med_name,dosage
                val row = "$now,$now,Pillbox (Shelly),1"
                dataManager?.writeMedicationData(row)

                // Optional: show a quick toast so the user knows it registered (needs main thread)
                mainHandler.post {
                    android.widget.Toast.makeText(context, "Pillbox opened - Medication logged!", android.widget.Toast.LENGTH_SHORT).show()
                }
            }
        }

        override fun onScanFailed(errorCode: Int) {
            super.onScanFailed(errorCode)
            Log.e(TAG, "Shelly BLE Scan failed with error code: $errorCode")
        }
    }

    fun startPairing(onDeviceFound: (String) -> Unit) {
        pairingCallback = onDeviceFound
        startScanning()
    }

    fun startPassive() {
        pairingCallback = null
        if (profile.shellyMacAddress.isEmpty()) {
            Log.d(TAG, "No Shelly MAC address paired. Passive scanner will log ANY Shelly Window open.")
            // You could alternatively return here if you ONLY want to scan when paired.
            // We'll scan anyway and if shellyMacAddress is empty, it accepts the first one it hears.
        }
        startScanning()
    }

    fun stopScanning() {
        if (!isScanning) return
        try {
            bleScanner?.stopScan(scanCallback)
            isScanning = false
            Log.d(TAG, "Shelly BLE scanning stopped.")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping BLE scan", e)
        }
    }

    private fun startScanning() {
        if (isScanning || bleScanner == null) return

        if (bluetoothAdapter?.isEnabled != true) {
            Log.w(TAG, "Bluetooth is disabled. Cannot start Shelly scanner.")
            return
        }

        try {
            val filter = ScanFilter.Builder()
                .setServiceData(BTHOME_SERVICE_UUID, byteArrayOf())
                .build()

            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()

            bleScanner.startScan(listOf(filter), settings, scanCallback)
            isScanning = true
            Log.d(TAG, "Shelly BLE scanning started.")
        } catch (e: SecurityException) {
            Log.e(TAG, "Missing BLUETOOTH_SCAN permission", e)
        } catch (e: Exception) {
            Log.e(TAG, "Error starting BLE scan", e)
        }
    }

    /**
     * Parses BTHome v2 payload to look for Object ID 0x1A (Window) with value 0x01 (Open)
     * OR Object ID 0x3A (Button) with any press value.
     * BTHome format: (Device Info Byte) (Object ID) (Value...)
     */
    private fun parseBTHomeAction(payload: ByteArray): Boolean {
        if (payload.isEmpty()) return false
        
        // Byte 0 is Device Info (e.g., bit 0 for encryption, bit 5-7 for version).
        // For BTHome v2, version is 010xxxxx (0x40).
        val deviceInfo = payload[0].toInt() and 0xFF
        if ((deviceInfo shr 5) != 2) return false // Not BTHome v2

        if ((deviceInfo and 0x01) == 1) {
            // Payload is encrypted, we can't parse it here without the bind key.
            Log.w(TAG, "Encrypted BTHome payload detected. Decryption not supported.")
            return false
        }

        var i = 1
        while (i < payload.size) {
            val objectId = payload[i].toInt() and 0xFF
            i++
            
            // Length of value depends on Object ID.
            if (objectId == 0x1A) { // Window
                if (i < payload.size) {
                    val value = payload[i].toInt() and 0xFF
                    if (value == 1) return true // 1 means Open
                    i += 1
                }
            } else if (objectId == 0x3A) { // Button
                if (i < payload.size) {
                    val value = payload[i].toInt() and 0xFF
                    if (value != 0) return true // Button pressed
                    i += 1
                }
            } else {
                // Skip the value for other Object IDs based on BTHome spec
                // Note: a robust parser would use a map of lengths for all BTHome Object IDs.
                // For simplicity, we are doing a quick advance. But wait, we must know the exact length
                // of each object to skip it!
                // To be safe, we'll implement a small lookup for common Shelly BLU Door/Window objects:
                // 0x00 (Packet ID): 1 byte
                // 0x01 (Battery): 1 byte
                // 0x05 (Illuminance): 3 bytes
                // 0x1A (Window): 1 byte
                // 0x20 (Moisture): 1 byte
                // 0x2D (Window Tilt): 1 byte
                // 0x3A (Button): 1 byte
                // 0x45 (Temperature): 2 bytes
                
                val len = getBTHomeObjectLength(objectId)
                i += len
            }
        }
        return false
    }

    private fun getBTHomeObjectLength(objectId: Int): Int {
        return when (objectId) {
            0x00, 0x01, 0x0F, 0x1A, 0x20, 0x2D, 0x3A -> 1
            0x02, 0x03, 0x45, 0x4A, 0x3F -> 2
            0x04, 0x05 -> 3
            0x08 -> 4
            else -> 1 // fallback (might fail parsing the rest, but we try)
        }
    }

    companion object {
        private const val TAG = "ShellyBleScanner"
    }
}
