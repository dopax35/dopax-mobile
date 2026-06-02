package com.pdcollect.app.data.model

data class AppEvent(
    val timestampMs: Long,
    val eventType: String,
    val packageName: String,
    val className: String
) {
    fun toCsvRow(): String = "$timestampMs,$eventType,$packageName,$className"
}
