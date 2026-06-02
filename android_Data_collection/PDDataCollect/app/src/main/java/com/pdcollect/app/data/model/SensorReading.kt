package com.pdcollect.app.data.model

data class SensorReading(
    val timestampNs: Long,
    val accelX: Float,
    val accelY: Float,
    val accelZ: Float,
    val gyroX: Float,
    val gyroY: Float,
    val gyroZ: Float,
    val magX: Float,
    val magY: Float,
    val magZ: Float
) {
    fun toCsvRow(): String =
        "$timestampNs,$accelX,$accelY,$accelZ,$gyroX,$gyroY,$gyroZ,$magX,$magY,$magZ"
}
