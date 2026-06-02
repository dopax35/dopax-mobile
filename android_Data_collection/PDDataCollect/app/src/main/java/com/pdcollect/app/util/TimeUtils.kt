package com.pdcollect.app.util

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object TimeUtils {
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    private val timestampFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    fun todayDateString(): String = dateFormat.format(Date())

    fun formatTimestamp(timeMs: Long): String = timestampFormat.format(Date(timeMs))

    fun currentTimeMs(): Long = System.currentTimeMillis()

    fun currentTimeNs(): Long = System.nanoTime()
}
