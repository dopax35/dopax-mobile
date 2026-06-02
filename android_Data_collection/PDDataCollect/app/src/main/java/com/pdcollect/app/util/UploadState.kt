package com.pdcollect.app.util

import java.io.File
import java.util.Locale

object UploadState {
    private const val UPLOADED_MARKER = ".uploaded"
    private const val UPLOADING_MARKER = ".uploading"
    private const val STALE_UPLOAD_MS = 6L * 60L * 60L * 1000L

    fun isUploaded(dateDir: File): Boolean {
        return File(dateDir, UPLOADED_MARKER).exists()
    }

    fun isUploadInProgress(dateDir: File, nowMs: Long = System.currentTimeMillis()): Boolean {
        val marker = File(dateDir, UPLOADING_MARKER)
        if (!marker.exists()) return false
        if (nowMs - marker.lastModified() > STALE_UPLOAD_MS) {
            marker.delete()
            return false
        }
        return true
    }

    fun tryClaimUpload(dateDir: File, nowMs: Long = System.currentTimeMillis()): Boolean {
        if (!dateDir.exists() || !dateDir.isDirectory) return false
        if (isUploaded(dateDir)) return false

        val marker = File(dateDir, UPLOADING_MARKER)
        if (marker.exists()) {
            if (nowMs - marker.lastModified() <= STALE_UPLOAD_MS) return false
            marker.delete()
        }

        return marker.createNewFile().also { claimed ->
            if (claimed) {
                marker.writeText("started_at_ms=$nowMs\n")
            }
        }
    }

    fun markUploaded(dateDir: File, filename: String, bytes: Long) {
        File(dateDir, UPLOADED_MARKER).writeText(
            buildString {
                append("uploaded_at_ms=").append(System.currentTimeMillis()).append('\n')
                append("filename=").append(filename).append('\n')
                append("bytes=").append(bytes).append('\n')
            }
        )
        clearUploadClaim(dateDir)
    }

    fun clearUploadClaim(dateDir: File) {
        File(dateDir, UPLOADING_MARKER).delete()
    }

    fun cloudFilename(userId: String, dateStr: String): String {
        return "PDData_${userId}_${dateStr}.zip"
    }

    fun uploadSessionId(userId: String, dateStr: String, bytes: Long): String {
        val safeUser = userId.ifBlank { "unknown" }.replace(Regex("[^A-Za-z0-9_-]"), "_")
        return String.format(Locale.US, "%s-%s-%d", safeUser, dateStr, bytes)
    }
}
