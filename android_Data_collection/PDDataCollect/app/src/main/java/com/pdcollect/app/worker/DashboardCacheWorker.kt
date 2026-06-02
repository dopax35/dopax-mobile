package com.pdcollect.app.worker

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import java.util.concurrent.TimeUnit

class DashboardCacheWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val profile = UserProfile(applicationContext)
        if (!profile.consentGiven || !profile.profileComplete) return Result.success()

        val dataManager = DataManager(applicationContext, profile)
        return try {
            dataManager.refreshDashboardGraphCache(
                trendDays = TREND_DAYS,
                maxSyncDates = MAX_SYNC_DATES_PER_RUN
            )
            Result.success()
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Dashboard graph cache refresh failed", e)
            Result.retry()
        } finally {
            dataManager.closeAll()
        }
    }

    companion object {
        private const val TAG = "DashboardCacheWorker"
        const val ONE_TIME_WORK_NAME = "DashboardCache.Refresh"
        private const val PERIODIC_WORK_NAME = "DashboardCache.Periodic"
        private const val TREND_DAYS = 180
        private const val MAX_SYNC_DATES_PER_RUN = 8

        fun enqueueRefresh(context: Context, initialDelaySeconds: Long = 0) {
            val req = OneTimeWorkRequestBuilder<DashboardCacheWorker>()
                .setInitialDelay(initialDelaySeconds, TimeUnit.SECONDS)
                .setConstraints(backgroundConstraints())
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.MINUTES)
                .addTag("dashboard_cache")
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                ONE_TIME_WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                req
            )
        }

        fun schedulePeriodic(context: Context) {
            val req = PeriodicWorkRequestBuilder<DashboardCacheWorker>(6, TimeUnit.HOURS)
                .setInitialDelay(30, TimeUnit.MINUTES)
                .setConstraints(backgroundConstraints())
                .addTag("dashboard_cache_periodic")
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                PERIODIC_WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                req
            )
        }

        private fun backgroundConstraints(): Constraints {
            return Constraints.Builder()
                .setRequiresBatteryNotLow(true)
                .setRequiresStorageNotLow(true)
                .build()
        }
    }
}
