package com.pdcollect.app.ui

import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.util.Constants
import com.pdcollect.app.util.TimeUtils
import java.io.File

class DebugDataPreviewActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_debug_data_preview)

        val profile = UserProfile(this)
        val dataManager = DataManager(this, profile)
        val dayDir = dataManager.getDayDir()
        val today = TimeUtils.todayDateString()
        // Only used to resolve dayDir above — close it immediately so its
        // background HandlerThread doesn't leak for the life of the app
        // process every time this (debug-trigger-reachable) screen opens.
        dataManager.closeAll()

        findViewById<TextView>(R.id.tvDateLabel).text = "Showing data for: $today\nPath: ${dayDir.absolutePath}"

        loadCsvPreview(dayDir, Constants.SENSORS_FILE, R.id.tvSensors)
        loadCsvPreview(dayDir, Constants.TOUCH_FILE, R.id.tvTouch)
        loadCsvPreview(dayDir, Constants.KEYS_FILE, R.id.tvKeys)
        loadCsvPreview(dayDir, Constants.APPS_FILE, R.id.tvApps)
        loadCsvPreview(dayDir, Constants.TMT_RESULTS_FILE, R.id.tvTmt)
        loadCsvPreview(dayDir, Constants.FACE_DISTANCE_FILE, R.id.tvFaceDistance)
        loadCsvPreview(dayDir, Constants.BEANIE_TEMP_FILE, R.id.tvBeanieTemperature)
        loadCsvPreview(dayDir, Constants.BEANIE_IMU_FILE, R.id.tvBeanieImu)
    }

    private fun loadCsvPreview(dayDir: File, filename: String, textViewId: Int) {
        val tv = findViewById<TextView>(textViewId)
        val file = File(dayDir, filename)

        if (!file.exists() || file.length() == 0L) {
            tv.text = "(no data yet)"
            return
        }

        tv.text = "Loading preview..."

        // Run in background thread to avoid ANR
        Thread {
            try {
                val tailInfo = readSmartTail(file)
                runOnUiThread {
                    if (isDestroyed || isFinishing) return@runOnUiThread
                    tv.text = tailInfo
                }
            } catch (e: Exception) {
                runOnUiThread {
                    if (isDestroyed || isFinishing) return@runOnUiThread
                    tv.text = "Error reading $filename: ${e.message}"
                }
            }
        }.start()
    }

    private fun readSmartTail(file: File): String {
        val startTime = System.currentTimeMillis()
        val totalSize = file.length()
        if (totalSize <= 0L) return "(no data yet)"

        val headerLine = file.bufferedReader().use { it.readLine() } ?: return "(no data yet)"
        val startSeek = (totalSize - MAX_PREVIEW_BYTES).coerceAtLeast(0L)
        val tailChunk = ByteArray((totalSize - startSeek).coerceAtMost(MAX_PREVIEW_BYTES).toInt())

        val actualRead = java.io.RandomAccessFile(file, "r").use { raf ->
            raf.seek(startSeek)
            raf.read(tailChunk, 0, tailChunk.size)
        }
        if (actualRead <= 0) return "(no data yet)"

        val chunkText = String(tailChunk, 0, actualRead, Charsets.UTF_8).replace("\r", "")
        val rawLines = chunkText.split('\n').toMutableList()
        if (startSeek > 0L && rawLines.isNotEmpty()) {
            rawLines.removeAt(0)
        }

        val previewLines = rawLines
            .map { it.trimEnd() }
            .filter { it.isNotBlank() }
            .takeLast(MAX_PREVIEW_LINES)
            .map { truncateLine(it) }

        val countEstimate = if (startSeek == 0L) {
            rawLines.count { it.isNotBlank() }
        } else {
            (totalSize / AVG_ROW_BYTES_HINT).coerceAtLeast(previewLines.size.toLong())
        }

        return buildString {
            if (startSeek > 0L) {
                append("[Showing last ${previewLines.size} rows of ~${countEstimate} total]\n")
            } else {
                append("[${countEstimate} total rows]\n")
            }
            append(truncateLine(headerLine))
            append('\n')
            if (startSeek > 0L) {
                append("... [preview truncated for safety] ...\n")
            }

            var usedChars = 0
            for (line in previewLines) {
                if (usedChars >= MAX_RENDER_CHARS) {
                    append("... [additional rows hidden] ...\n")
                    break
                }
                append(line)
                append('\n')
                usedChars += line.length
            }

            val duration = System.currentTimeMillis() - startTime
            append("\n(Read in ${duration}ms)")
        }.trimEnd()
    }

    private fun truncateLine(line: String): String {
        if (line.length <= MAX_LINE_CHARS) return line
        return line.take(MAX_LINE_CHARS) + " ... [line truncated]"
    }

    companion object {
        private const val MAX_PREVIEW_BYTES = 64 * 1024L
        private const val MAX_PREVIEW_LINES = 20
        private const val MAX_LINE_CHARS = 400
        private const val MAX_RENDER_CHARS = 8_000
        private const val AVG_ROW_BYTES_HINT = 150L
    }
}
