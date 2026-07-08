package com.pdcollect.app.ui

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
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
import com.pdcollect.app.service.BeanieDiscovery
import com.pdcollect.app.service.BeanieStatusStore
import com.pdcollect.app.service.BeanieService
import java.util.Locale

class BeanieDevicePickerActivity : AppCompatActivity() {

    private lateinit var profile: UserProfile
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bleScanner: BluetoothLeScanner? = null

    private val foundDevices = mutableMapOf<String, String>()
    private var isScanning = false
    private val scanHandler = Handler(Looper.getMainLooper())
    private val scanTimeoutMs = 20_000L
    private val btPermissionRequest = 3002

    private lateinit var tvCurrentDevice: TextView
    private lateinit var tvBeanieStatus: TextView
    private lateinit var tvCurrentTemp: TextView
    private lateinit var tvCurrentHeatFlux: TextView
    private lateinit var viewBeanieDot: View
    private lateinit var layoutScanning: LinearLayout
    private lateinit var tvDevicesHeader: TextView
    private lateinit var deviceListContainer: LinearLayout
    private lateinit var btnScan: MaterialButton
    private lateinit var btnDisconnect: MaterialButton

    private val beanieReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val connected = intent.getBooleanExtra(BeanieService.EXTRA_CONNECTED, false)
            val name = intent.getStringExtra(BeanieService.EXTRA_DEVICE_NAME) ?: ""
            val status = intent.getStringExtra(BeanieService.EXTRA_STATUS) ?: BeanieService.STATUS_IDLE
            val tskin = if (intent.hasExtra(BeanieService.EXTRA_TSKIN_C)) {
                intent.getDoubleExtra(BeanieService.EXTRA_TSKIN_C, Double.NaN)
            } else {
                Double.NaN
            }
            val heatFlux = if (intent.hasExtra(BeanieService.EXTRA_HEAT_FLUX)) {
                intent.getDoubleExtra(BeanieService.EXTRA_HEAT_FLUX, Double.NaN)
            } else {
                Double.NaN
            }

            tvBeanieStatus.text = if (connected) "Connected - $name" else status
            viewBeanieDot.backgroundTintList = android.content.res.ColorStateList.valueOf(
                ContextCompat.getColor(
                    context, if (connected) R.color.status_success else R.color.gray_50
                )
            )
            tvCurrentTemp.text = if (tskin.isFinite()) {
                String.format(Locale.US, "%.2f C", tskin)
            } else {
                "-- C"
            }
            tvCurrentHeatFlux.text = if (heatFlux.isFinite()) {
                String.format(Locale.US, "%.2f cal/s", heatFlux)
            } else {
                "-- cal/s"
            }
            refreshCurrentDeviceUi()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_beanie_device_picker)

        profile = UserProfile(this)
        val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = btManager?.adapter
        bleScanner = bluetoothAdapter?.bluetoothLeScanner

        tvCurrentDevice = findViewById(R.id.tvCurrentBeanieDevice)
        tvBeanieStatus = findViewById(R.id.tvBeanieStatus)
        tvCurrentTemp = findViewById(R.id.tvCurrentBeanieTemp)
        tvCurrentHeatFlux = findViewById(R.id.tvCurrentBeanieHeatFlux)
        viewBeanieDot = findViewById(R.id.viewBeanieDot)
        layoutScanning = findViewById(R.id.layoutBeanieScanning)
        tvDevicesHeader = findViewById(R.id.tvBeanieDevicesHeader)
        deviceListContainer = findViewById(R.id.beanieDeviceListContainer)
        btnScan = findViewById(R.id.btnScanBeanieDevices)
        btnDisconnect = findViewById(R.id.btnDisconnectBeanie)

        refreshCurrentDeviceUi()

        btnScan.setOnClickListener { requestPermissionsAndScan() }
        btnDisconnect.setOnClickListener {
            BeanieService.stop(this)
            BeanieStatusStore.clear(this)
            profile.beanieDeviceAddress = ""
            profile.beanieDeviceName = ""
            refreshCurrentDeviceUi()
            Toast.makeText(this, "Beanie removed", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onResume() {
        super.onResume()
        refreshCurrentDeviceUi()
        ContextCompat.registerReceiver(
            this,
            beanieReceiver,
            IntentFilter(BeanieService.ACTION_BEANIE_UPDATE),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
    }

    override fun onPause() {
        super.onPause()
        try {
            unregisterReceiver(beanieReceiver)
        } catch (_: Exception) {
        }
        stopScan()
    }

    private fun requestPermissionsAndScan() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val required = arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
            val missing = required.filter {
                ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
            }
            if (missing.isNotEmpty()) {
                ActivityCompat.requestPermissions(this, missing.toTypedArray(), btPermissionRequest)
                return
            }
        }
        startScan()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == btPermissionRequest && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            startScan()
        }
    }

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
        btnScan.text = "Scanning..."

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        try {
            @Suppress("MissingPermission")
            bleScanner?.startScan(null, settings, scanCallback)
            scanHandler.postDelayed({ stopScan() }, scanTimeoutMs)
        } catch (_: SecurityException) {
            stopScan()
            Toast.makeText(this, "Bluetooth permission denied while scanning", Toast.LENGTH_SHORT).show()
        }
    }

    private fun stopScan() {
        if (!isScanning) return
        isScanning = false
        scanHandler.removeCallbacksAndMessages(null)
        try {
            @Suppress("MissingPermission")
            bleScanner?.stopScan(scanCallback)
        } catch (_: Exception) {
        }

        layoutScanning.visibility = View.GONE
        btnScan.isEnabled = true
        btnScan.text = "Scan for Beanies"
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            if (!BeanieDiscovery.isLikelyBeanie(result)) return
            val address = result.device.address
            val name = BeanieDiscovery.displayName(result).takeIf { it.isNotBlank() } ?: "Beanie ($address)"
            if (foundDevices.containsKey(address)) return

            foundDevices[address] = name
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                addDeviceRow(address, name)
            }
        }

        override fun onScanFailed(errorCode: Int) {
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                stopScan()
                Toast.makeText(this@BeanieDevicePickerActivity, "Scan failed (error $errorCode)", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun addDeviceRow(address: String, name: String) {
        tvDevicesHeader.visibility = View.VISIBLE

        val card = MaterialCardView(this).apply {
            radius = 16f * resources.displayMetrics.density
            cardElevation = 0f
            setCardBackgroundColor(
                android.content.res.ColorStateList.valueOf(
                    ContextCompat.getColor(this@BeanieDevicePickerActivity, R.color.surface_container_low)
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
            setTextColor(ContextCompat.getColor(this@BeanieDevicePickerActivity, R.color.on_surface))
            setTypeface(null, android.graphics.Typeface.BOLD)
        })
        inner.addView(TextView(this).apply {
            text = address
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 12f)
            setTextColor(ContextCompat.getColor(this@BeanieDevicePickerActivity, R.color.secondary))
        })

        card.addView(inner)
        deviceListContainer.addView(card)
    }

    private fun pairDevice(address: String, name: String) {
        stopScan()
        profile.beanieDeviceAddress = address
        profile.beanieDeviceName = name
        BeanieService.stop(this)
        Handler(Looper.getMainLooper()).postDelayed({
            BeanieService.start(this)
        }, 500)
        deviceListContainer.removeAllViews()
        tvDevicesHeader.visibility = View.GONE
        refreshCurrentDeviceUi()
        Toast.makeText(this, "Connecting to $name...", Toast.LENGTH_SHORT).show()
    }

    private fun refreshCurrentDeviceUi() {
        val address = profile.beanieDeviceAddress
        val name = profile.beanieDeviceName

        tvCurrentDevice.text = if (address.isBlank()) "No Beanie paired" else name.ifBlank { address }
        btnDisconnect.visibility = if (address.isBlank()) View.GONE else View.VISIBLE
        if (address.isBlank()) {
            tvBeanieStatus.text = "Not set up"
            tvCurrentTemp.text = "-- C"
            tvCurrentHeatFlux.text = "-- cal/s"
            viewBeanieDot.backgroundTintList = android.content.res.ColorStateList.valueOf(
                ContextCompat.getColor(this, R.color.gray_50)
            )
            return
        }

        val snapshot = BeanieStatusStore.load(this)
        tvBeanieStatus.text = if (snapshot?.connected == true) {
            "Connected - ${snapshot.deviceName.ifBlank { name.ifBlank { address } }}"
        } else {
            snapshot?.status ?: "Checking status..."
        }
        viewBeanieDot.backgroundTintList = android.content.res.ColorStateList.valueOf(
            ContextCompat.getColor(
                this, if (snapshot?.connected == true) R.color.status_success else R.color.gray_50
            )
        )
        tvCurrentTemp.text = if ((snapshot?.tskinC ?: Double.NaN).isFinite()) {
            String.format(Locale.US, "%.2f C", snapshot!!.tskinC)
        } else {
            "-- C"
        }
        tvCurrentHeatFlux.text = if ((snapshot?.heatFluxCalPerSec ?: Double.NaN).isFinite()) {
            String.format(Locale.US, "%.2f cal/s", snapshot!!.heatFluxCalPerSec)
        } else {
            "-- cal/s"
        }
    }
}
