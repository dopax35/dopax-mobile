package com.pdcollect.app.util

import android.content.Context
import android.content.Intent
import com.pdcollect.app.ui.CrashReportActivity
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.*

/**
 * Global crash handler that writes a detailed stack trace to disk and then
 * launches CrashReportActivity so the user can share the log.
 */
class CrashHandler(private val context: Context) : Thread.UncaughtExceptionHandler {

    private val defaultHandler: Thread.UncaughtExceptionHandler? =
        Thread.getDefaultUncaughtExceptionHandler()

    override fun uncaughtException(thread: Thread, throwable: Throwable) {
        try {
            val sw = StringWriter()
            throwable.printStackTrace(PrintWriter(sw))

            val sdf = SimpleDateFormat("yyyy-MM-dd_HH-mm-ss", Locale.US)
            val sdfReadable = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
            val now = Date()

            val logDir = File(context.getExternalFilesDir(null), "crash_logs").apply { mkdirs() }
            val logFile = File(logDir, "crash_${sdf.format(now)}.txt")

            val pkgInfo = runCatching {
                context.packageManager.getPackageInfo(context.packageName, 0)
            }.getOrNull()

            logFile.writeText(buildString {
                appendLine("DopaX Crash Report")
                appendLine("==================")
                appendLine("Time     : ${sdfReadable.format(now)}")
                appendLine("Thread   : ${thread.name}")
                appendLine("Version  : ${pkgInfo?.versionName ?: "unknown"}")
                appendLine("Build    : ${pkgInfo?.longVersionCode ?: "unknown"}")
                appendLine()
                appendLine("Exception: ${throwable.javaClass.name}")
                appendLine("Message  : ${throwable.message}")
                appendLine()
                appendLine("Stack Trace:")
                append(sw.toString())
            })

            // Launch CrashReportActivity in a fresh task
            val intent = Intent(context, CrashReportActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                putExtra(CrashReportActivity.EXTRA_LOG_PATH, logFile.absolutePath)
                putExtra(CrashReportActivity.EXTRA_SUMMARY,
                    "${throwable.javaClass.simpleName}: ${throwable.message ?: "Unexpected error"}")
            }
            context.startActivity(intent)

        } catch (_: Exception) {
            // Never let the crash handler itself crash — fall through to default
        }

        // Still call the system default so Android can do its own crash reporting
        defaultHandler?.uncaughtException(thread, throwable)
    }
}
