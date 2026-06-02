package com.pdcollect.app.data.model

data class TouchEvent(
    val timestampMs: Long,
    val eventType: String,
    val x: Int,
    val y: Int,
    val sourceApp: String
) {
    fun toCsvRow(): String = "$timestampMs,$eventType,$x,$y,$sourceApp"
}
