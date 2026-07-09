package com.pdcollect.app.service

import android.content.Context

data class BeanieStatusSnapshot(
    val connected: Boolean,
    val status: String,
    val deviceName: String,
    val tskinC: Double,
    val heatFluxCalPerSec: Double,
    val batteryPct: Int?,
    // Added for the Beanie ML activity-inference feature. Default values keep this
    // change source-compatible with every pre-existing named-argument call site.
    val activityLabel: String? = null,
    val activityConfidence: Double? = null
)

object BeanieStatusStore {
    private const val PREFS = "beanie_status_store"
    private const val KEY_PRESENT = "present"
    private const val KEY_CONNECTED = "connected"
    private const val KEY_STATUS = "status"
    private const val KEY_DEVICE_NAME = "device_name"
    private const val KEY_TSKIN_C = "tskin_c"
    private const val KEY_HEAT_FLUX = "heat_flux"
    private const val KEY_BATTERY_PCT = "battery_pct"
    private const val KEY_ACTIVITY_LABEL = "activity_label"
    private const val KEY_ACTIVITY_CONFIDENCE = "activity_confidence"

    fun save(context: Context, snapshot: BeanieStatusSnapshot) {
        val normalized = snapshot.normalized()
        if (load(context) == normalized) return
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
            putBoolean(KEY_PRESENT, true)
            putBoolean(KEY_CONNECTED, normalized.connected)
            putString(KEY_STATUS, normalized.status)
            putString(KEY_DEVICE_NAME, normalized.deviceName)
            putFiniteDouble(KEY_TSKIN_C, normalized.tskinC)
            putFiniteDouble(KEY_HEAT_FLUX, normalized.heatFluxCalPerSec)
            if (normalized.batteryPct != null) {
                putInt(KEY_BATTERY_PCT, normalized.batteryPct)
            } else {
                remove(KEY_BATTERY_PCT)
            }
            if (!normalized.activityLabel.isNullOrEmpty()) {
                putString(KEY_ACTIVITY_LABEL, normalized.activityLabel)
            } else {
                remove(KEY_ACTIVITY_LABEL)
            }
            if (normalized.activityConfidence != null) {
                putFiniteDouble(KEY_ACTIVITY_CONFIDENCE, normalized.activityConfidence)
            } else {
                remove(KEY_ACTIVITY_CONFIDENCE)
            }
        }.apply()
    }

    fun load(context: Context): BeanieStatusSnapshot? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_PRESENT, false)) return null
        return BeanieStatusSnapshot(
            connected = prefs.getBoolean(KEY_CONNECTED, false),
            status = prefs.getString(KEY_STATUS, BeanieService.STATUS_IDLE).orEmpty(),
            deviceName = prefs.getString(KEY_DEVICE_NAME, "").orEmpty(),
            tskinC = prefs.getString(KEY_TSKIN_C, null)?.toDoubleOrNull() ?: Double.NaN,
            heatFluxCalPerSec = prefs.getString(KEY_HEAT_FLUX, null)?.toDoubleOrNull() ?: Double.NaN,
            batteryPct = if (prefs.contains(KEY_BATTERY_PCT)) prefs.getInt(KEY_BATTERY_PCT, 0) else null,
            activityLabel = prefs.getString(KEY_ACTIVITY_LABEL, null),
            activityConfidence = prefs.getString(KEY_ACTIVITY_CONFIDENCE, null)?.toDoubleOrNull()
        )
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    private fun android.content.SharedPreferences.Editor.putFiniteDouble(key: String, value: Double) {
        if (value.isFinite()) {
            putString(key, value.toString())
        } else {
            remove(key)
        }
    }

    private fun BeanieStatusSnapshot.normalized(): BeanieStatusSnapshot {
        return copy(
            tskinC = tskinC.roundForUi(),
            heatFluxCalPerSec = heatFluxCalPerSec.roundForUi(),
            deviceName = deviceName.trim()
        )
    }

    private fun Double.roundForUi(): Double {
        if (!isFinite()) return Double.NaN
        return kotlin.math.round(this * 100.0) / 100.0
    }
}
