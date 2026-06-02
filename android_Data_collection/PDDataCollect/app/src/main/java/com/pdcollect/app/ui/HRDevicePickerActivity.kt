package com.pdcollect.app.ui

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.pdcollect.app.R
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.service.AntHRService
import com.pdcollect.app.util.Constants

class HRDevicePickerActivity : AppCompatActivity() {

    private lateinit var profile: UserProfile
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bleScanner: BluetoothLeScanner? = null

    private val foundDevices = mutableMapOf<String, String>() // address -> name
    private var isScanning = false
    private val scanHandler = Handler(Looper.getMainLooper())
    private val SCAN_TIMEOUT_MS = 15_000L
    private val BT_PERMISSION_REQUEST = 3001

    private lateinit var tvCurrentDevice: TextView
    private lateinit var tvHrStatus: TextView
    private lateinit var tvCurrentBpm: TextView
    private lateinit var viewHrDot: View
    private lateinit var layoutScanning: LinearLayout
    private lateinit var tvDevicesHeader: TextView
    private lateinit var deviceListContainer: LinearLayout
    private lateinit var btnScan: MaterialButton
    private lateinit var btnDisconnect: MaterialButton

    // BroadcastReceiver to receive live BPM updates from AntHRService
    private val hrUpdateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val connected = intent.getBooleanExtra(AntHRService.EXTRA_CONNECTED, false)
            val bpm = intent.getIntExtra(AntHRService.EXTRA_BPM, 0)
            val name = intent.getStringExtra(AntHRService.EXTRA_DEVICE_NAME) ?: ""
            val status = intent.getStringExtra(AntHRService.EXTRA_STATUS)

            if (connected) {
                tvCurrentBpm.text = if (bpm > 0) "$bpm bpm" else status ?: "Ready"
                tvHrStatus.text = "Connected · $name"
                viewHrDot.backgroundTintList = android.content.res.ColorStateList.valueOf(
                    android.graphics.Color.parseColor("#43A047")
                )
            } else {
                tvCurrentBpm.text = "— bpm"
                tvHrStatus.text = status ?: "Disconnected"
                viewHrDot.backgroundTintList = android.content.res.ColorStateList.valueOf(
                    android.graphics.Color.parseColor("#9E9E9E")
                )
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_hr_device_picker)

        profile = UserProfile(this)
        val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = btManager?.adapter
        bleScanner = bluetoothAdapter?.bluetoothLeScanner

        // Bind views
        tvCurrentDevice = findViewById(R.id.tvCurrentDevice)
        tvHrStatus = findViewById(R.id.tvHrStatus)
        tvCurrentBpm = findViewById(R.id.tvCurrentBpm)
        viewHrDot = findViewById(R.id.viewHrDot)
        layoutScanning = findViewById(R.id.layoutScanning)
        tvDevicesHeader = findViewById(R.id.tvDevicesHeader)
        deviceListContainer = findViewById(R.id.deviceListContainer)
        btnScan = findViewById(R.id.btnScanDevices)
        btnDisconnect = findViewById(R.id.btnDisconnect)

        // Show current paired device
        refreshCurrentDeviceUI()

        btnScan.setOnClickListener { requestPermissionsAndScan() }

        btnDisconnect.setOnClickListener {
            AntHRService.stop(this)
            profile.hrDeviceAddress = ""
            profile.hrDeviceName = ""
            refreshCurrentDeviceUI()
            Toast.makeText(this, "Device removed", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onResume() {
        super.onResume()
        refreshCurrentDeviceUI()
        val filter = IntentFilter(AntHRService.ACTION_HR_UPDATE)
        ContextCompat.registerReceiver(
            this,
            hrUpdateReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    override fun onPause() {
        super.onPause()
        try { unregisterReceiver(hrUpdateReceiver) } catch (_: Exception) {}
        stopScan()
    }

    // ─── Permission handling ─────────────────────────────────────────────────────

    private fun requestPermissionsAndScan() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val required = arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
            val missing = required.filter {
                ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
            }
            if (missing.isNotEmpty()) {
                ActivityCompat.requestPermissions(this, missing.toTypedArray(), BT_PERMISSION_REQUEST)
                return
            }
        }
        startScan()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == BT_PERMISSION_REQUEST) {
            if (grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
                startScan()
            } else {
                Toast.makeText(this, "Bluetooth permissions required to scan", Toast.LENGTH_LONG).show()
            }
        }
    }

    // ─── BLE Scan ────────────────────────────────────────────────────────────────

    private fun startScan() {
        val adapter = bluetoothAdapter
        if (adapter == null || !adapter.isEnabled) {
            Toast.makeText(this, "Please enable Bluetooth first", Toast.LENGTH_LONG).show()
            return
        }

        if (isScanning) return
        isScanning = true
        foundDevices.clear()
        deviceListContainer.removeAllViews()

        layoutScanning.visibility = View.VISIBLE
        tvDevicesHeader.visibility = View.GONE
        btnScan.isEnabled = false
        btnScan.text = "Scanning…"

        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(AntHRService.HR_SERVICE_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        @Suppress("MissingPermission")
        bleScanner?.startScan(listOf(filter), settings, scanCallback)

        // Auto-stop after timeout
        scanHandler.postDelayed({ stopScan() }, SCAN_TIMEOUT_MS)
    }

    private fun stopScan() {
        if (!isScanning) return
        isScanning = false
        scanHandler.removeCallbacksAndMessages(null)
        try { 
            @Suppress("MissingPermission")
            bleScanner?.stopScan(scanCallback) 
        } catch (_: Exception) {}

        runOnUiThread {
            layoutScanning.visibility = View.GONE
            btnScan.isEnabled = true
            btnScan.text = "Scan for HR Devices"
            if (foundDevices.isEmpty()) {
                tvDevicesHeader.visibility = View.GONE
                Toast.makeText(this, "No HR devices found. Make sure your strap is active.", Toast.LENGTH_LONG).show()
            }
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val address = result.device.address
            @Suppress("MissingPermission")
            val name = result.device.name?.takeIf { it.isNotBlank() } ?: "HR Device ($address)"
            if (foundDevices.containsKey(address)) return

            foundDevices[address] = name
            runOnUiThread { addDeviceRow(address, name) }
        }

        override fun onScanFailed(errorCode: Int) {
            runOnUiThread {
                Toast.makeText(this@HRDevicePickerActivity, "Scan failed (error $errorCode)", Toast.LENGTH_SHORT).show()
                stopScan()
            }
        }
    }

    // ─── UI ──────────────────────────────────────────────────────────────────────

    private fun addDeviceRow(address: String, name: String) {
        tvDevicesHeader.visibility = View.VISIBLE

        val card = MaterialCardView(this).apply {
            radius = 16f * resources.displayMetrics.density
            cardElevation = 0f
            setCardBackgroundColor(
                android.content.res.ColorStateList.valueOf(
                    ContextCompat.getColor(this@HRDevicePickerActivity, R.color.surface_container_low)
                )
            )
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { bottomMargin = (12 * resources.displayMetrics.density).toInt() }
            isClickable = true
            isFocusable = true
            setOnClickListener { pairDevice(address, name) }
        }

        val inner = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val pad = (20 * resources.displayMetrics.density).toInt()
            setPadding(pad, pad, pad, pad)
        }

        inner.addView(TextView(this).apply {
            text = name
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 16f)
            setTextColor(ContextCompat.getColor(this@HRDevicePickerActivity, R.color.on_surface))
            setTypeface(null, android.graphics.Typeface.BOLD)
        })
        inner.addView(TextView(this).apply {
            text = address
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 12f)
            setTextColor(ContextCompat.getColor(this@HRDevicePickerActivity, R.color.secondary))
        })

        card.addView(inner)
        deviceListContainer.addView(card)
    }

    private fun pairDevice(address: String, name: String) {
        stopScan()
        profile.hrDeviceAddress = address
        profile.hrDeviceName = name

        // Stop and restart the HR service so it connects to the selected device
        AntHRService.stop(this)
        Handler(Looper.getMainLooper()).postDelayed({
            AntHRService.start(this)
        }, 500)

        deviceListContainer.removeAllViews()
        tvDevicesHeader.visibility = View.GONE
        refreshCurrentDeviceUI()
        Toast.makeText(this, "Connecting to $name…", Toast.LENGTH_SHORT).show()
    }

    private fun refreshCurrentDeviceUI() {
        val addr = profile.hrDeviceAddress
        val name = profile.hrDeviceName

        if (addr.isBlank()) {
            tvCurrentDevice.text = "No device paired"
            btnDisconnect.visibility = View.GONE
        } else {
            tvCurrentDevice.text = name.ifBlank { addr }
            btnDisconnect.visibility = View.VISIBLE
        }
        tvCurrentBpm.text = "— bpm"
        tvHrStatus.text = if (addr.isBlank()) "Not set up" else "Checking Status…"
    }
}
