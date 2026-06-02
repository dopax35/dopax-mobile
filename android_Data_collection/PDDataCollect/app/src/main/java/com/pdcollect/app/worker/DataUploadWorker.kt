package com.pdcollect.app.worker

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.util.CloudUploader
import com.pdcollect.app.util.UploadState
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * Two-tier upload pipeline:
 *
 *   1. [DailyUploadDispatcher] is a *periodic* worker that fires once per day
 *      at ~02:00. Its only job is to enqueue [DataUploadWorker] one-time
 *      requests. It does no I/O of its own, so it never needs to retry.
 *
 *   2. [DataUploadWorker] is a *one-time* worker that does the real upload.
 *      It runs with EXPONENTIAL backoff, so a transient failure (no Wi-Fi,
 *      flaky network, server hiccup) is retried within minutes — not 24 h
 *      later as the previous Periodic-only design did.
 *
 *      The dispatcher enqueues two one-time runs:
 *        • a Wi-Fi (UNMETERED) run with no initial delay
 *        • a "cellular fallback" run delayed 12 h that runs on any network
 *      Both share the on-disk `.uploaded` marker per date directory, so
 *      whichever runs first wins and the other is a no-op.
 */
class DataUploadWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val profile = UserProfile(applicationContext)
        if (!profile.autoUploadEnabled) {
            return Result.success()
        }

        val dataManager = DataManager(applicationContext, profile)
        val todayStr = com.pdcollect.app.util.TimeUtils.todayDateString()

        var allSuccess = true
        try {
            val dates = dataManager.listAvailableDates()
            android.util.Log.d(TAG, "Processing backlog: ${dates.size} days found")
            for (entry in dates) {
                val dateStr = entry.date
                if (dateStr == todayStr) continue

                runCatching {
                    val dateDir = java.io.File(dataManager.getStoragePath(), dateStr)
                    if (entry.isUploaded || UploadState.isUploaded(dateDir)) return@runCatching
                    if (!dataManager.dateHasRecordedData(dateStr)) {
                        android.util.Log.d(TAG, "Skipping $dateStr; no recorded data rows")
                        return@runCatching
                    }
                    if (!UploadState.tryClaimUpload(dateDir)) {
                        android.util.Log.d(TAG, "Skipping $dateStr; upload already completed or in progress")
                        return@runCatching
                    }

                    var uploadSucceeded = false
                    var zipFile: java.io.File? = null
                    try {
                        zipFile = dataManager.zipDateData(dateStr)
                        val zip = zipFile
                        if (zip == null || !zip.exists() || zip.length() <= 0L) {
                            allSuccess = false
                            android.util.Log.w(TAG, "Failed to create non-empty zip for $dateStr")
                            return@runCatching
                        }

                        android.util.Log.d(TAG, "Uploading $dateStr (${zip.length()} bytes)")
                        uploadSucceeded = CloudUploader.uploadZipFileSync(zip, profile.userId, dateStr)
                        if (uploadSucceeded) {
                            UploadState.markUploaded(
                                dateDir,
                                UploadState.cloudFilename(profile.userId, dateStr),
                                zip.length()
                            )
                            android.util.Log.d(TAG, "Successfully uploaded $dateStr")
                        } else {
                            allSuccess = false
                            android.util.Log.w(TAG, "Failed to upload $dateStr")
                        }
                    } finally {
                        zipFile?.delete()
                        if (!uploadSucceeded) {
                            UploadState.clearUploadClaim(dateDir)
                        }
                    }
                    if (!uploadSucceeded) {
                        allSuccess = false
                    }
                }.onFailure {
                    android.util.Log.e(TAG, "Error processing $dateStr", it)
                    allSuccess = false
                }
            }
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Upload loop failed", e)
            allSuccess = false
        }

        // Sync latest profile and dashboard metrics to Firestore
        runCatching {
            com.pdcollect.app.data.FirebaseSyncManager.saveProfileToCloud(profile, dataManager)
        }.onFailure {
            android.util.Log.e(TAG, "Firestore sync failed", it)
        }

        // Maintenance: 
        // 1. Delete raw data uploaded > 7 days ago.
        // 2. Delete ALL data older than 1 year.
        // 3. Ensure graph summaries are consistent before raw deletion.
        runCatching { 
            dataManager.refreshDashboardGraphCache(trendDays = 180, maxSyncDates = 8)
            dataManager.cleanupOldData(daysToKeep = 365)
            dataManager.cleanupUploadedRawData() 
        }.onFailure { android.util.Log.e(TAG, "Storage maintenance failed", it) }

        dataManager.closeAll()
        return if (allSuccess) Result.success() else Result.retry()
    }

    companion object {
        private const val TAG = "DataUploadWorker"
        private const val ONE_TIME_WORK_WIFI = "DataUpload.OneTime.WiFi"
        private const val ONE_TIME_WORK_FALLBACK = "DataUpload.OneTime.Fallback"

        /**
         * Backwards-compatible entry point used by MainActivity and BootReceiver.
         * Delegates to [DailyUploadDispatcher.scheduleDaily].
         */
        fun scheduleDaily(context: Context) {
            DailyUploadDispatcher.scheduleDaily(context)
            DashboardCacheWorker.schedulePeriodic(context)
        }

        /** Build a one-time upload request with the given network constraint and delay. */
        internal fun oneTimeRequest(
            networkType: NetworkType,
            initialDelayMinutes: Long
        ) = OneTimeWorkRequestBuilder<DataUploadWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(networkType)
                    .setRequiresBatteryNotLow(true)
                    .build()
            )
            .setInitialDelay(initialDelayMinutes, TimeUnit.MINUTES)
            // Exponential backoff: 10m → 20m → 40m → … capped by WorkManager at 5h.
            // With CONNECTED constraint, the platform will also defer until network
            // is available, so transient outages don't burn retries.
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.MINUTES)
            .addTag("auto_upload")
            .build()

        /**
         * Enqueue both the Wi-Fi-preferred and cellular-fallback one-time runs.
         * Idempotent because of the per-date `.uploaded` marker file.
         */
        fun enqueueOneTimeUploads(context: Context) {
            val wm = WorkManager.getInstance(context)
            wm.enqueueUniqueWork(
                ONE_TIME_WORK_WIFI,
                ExistingWorkPolicy.REPLACE,
                oneTimeRequest(NetworkType.UNMETERED, initialDelayMinutes = 0)
            )
            wm.enqueueUniqueWork(
                ONE_TIME_WORK_FALLBACK,
                ExistingWorkPolicy.REPLACE,
                oneTimeRequest(NetworkType.CONNECTED, initialDelayMinutes = 12 * 60)
            )
            android.util.Log.d(TAG, "Enqueued Wi-Fi upload (immediate) + cellular fallback (+12h)")
        }
    }
}

/**
 * Periodic worker that fires daily at ~02:00 and enqueues the real upload work.
 * Doing only enqueueing here means this worker can never enter a retry-storm —
 * the heavy lifting happens in [DataUploadWorker] which has proper exponential
 * backoff.
 */
class DailyUploadDispatcher(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val profile = UserProfile(applicationContext)
        if (!profile.autoUploadEnabled) return Result.success()
        DataUploadWorker.enqueueOneTimeUploads(applicationContext)
        return Result.success()
    }

    companion object {
        private const val WORK_NAME = "DailyUploadDispatcher"

        fun scheduleDaily(context: Context) {
            val profile = UserProfile(context)
            val wm = WorkManager.getInstance(context)
            if (!profile.autoUploadEnabled) {
                wm.cancelUniqueWork(WORK_NAME)
                wm.cancelAllWorkByTag("auto_upload")
                return
            }

            val now = Calendar.getInstance()
            val due = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 2)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                if (before(now)) add(Calendar.HOUR_OF_DAY, 24)
            }
            val initialDelay = due.timeInMillis - now.timeInMillis

            // The dispatcher does no network I/O — no constraints needed.
            val req = PeriodicWorkRequestBuilder<DailyUploadDispatcher>(24, TimeUnit.HOURS)
                .setInitialDelay(initialDelay, TimeUnit.MILLISECONDS)
                .addTag("auto_upload_dispatcher")
                .build()

            wm.enqueueUniquePeriodicWork(
                WORK_NAME,
                // KEEP — don't reset the daily clock just because the user opened
                // the app. REPLACE caused the previous design to drift.
                ExistingPeriodicWorkPolicy.KEEP,
                req
            )
            android.util.Log.d(
                "DailyUploadDispatcher",
                "Daily dispatch scheduled. Next fire in ${initialDelay / 1000 / 60} min"
            )
        }
    }
}
