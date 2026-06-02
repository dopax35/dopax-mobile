package com.pdcollect.app.ui

import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ShareCompat
import androidx.core.content.FileProvider
import com.pdcollect.app.R
import java.io.File

class CrashReportActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_LOG_PATH = "CRASH_LOG_PATH"
        const val EXTRA_SUMMARY  = "CRASH_SUMMARY"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_crash_report)

        val logPath = intent.getStringExtra(EXTRA_LOG_PATH)
        val summary = intent.getStringExtra(EXTRA_SUMMARY) ?: "Unexpected crash"

        findViewById<TextView>(R.id.tvCrashSummary).text = summary

        // Show log snippet if available
        logPath?.let { path ->
            val file = File(path)
            if (file.exists()) {
                val snippet = file.readLines().take(30).joinToString("\n")
                findViewById<TextView>(R.id.tvCrashLog).text = snippet
            }
        }

        findViewById<Button>(R.id.btnSendCrash).setOnClickListener {
            logPath?.let { path ->
                val file = File(path)
                if (file.exists()) {
                    val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                    ShareCompat.IntentBuilder(this)
                        .setType("text/plain")
                        .setSubject("dopa-X Crash Report")
                        .setStream(uri)
                        .setChooserTitle("Send crash report via…")
                        .startChooser()
                }
            }
        }

        findViewById<Button>(R.id.btnDismissCrash).setOnClickListener { finish() }
    }
}

