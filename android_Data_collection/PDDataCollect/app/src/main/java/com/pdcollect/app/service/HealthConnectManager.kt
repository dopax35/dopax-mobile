package com.pdcollect.app.service

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.pdcollect.app.data.model.ExternalActivitySample
import com.pdcollect.app.data.model.SleepSample
import java.time.Duration
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * Reads exercise sessions the user already logged in Health Connect (fed by
 * Google Fit, Samsung Health, Strava-via-Health-Connect, etc.) so they don't
 * have to re-enter workouts by hand. Read-only — this app never writes to
 * Health Connect.
 *
 * NOTE for the implementing programmer: this targets connect-client 1.1.0
 * (latest stable as of July 2026). Exercise-type mapping below prioritizes
 * the session title text over Health Connect's numeric exercise-type
 * constant, since the full constant set is large and still evolving —
 * verify mapExerciseType() against the current SDK during integration and
 * extend the title-keyword list or numeric cases as needed.
 */
object HealthConnectManager {

    val PERMISSIONS = setOf(
        HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(HeartRateRecord::class)
    )

    // Requested separately from PERMISSIONS above: sleep is an independent
    // feature the user can grant or deny on its own. Bundling it into one
    // combined set would mean denying either half blocks BOTH imports — see
    // MainActivity's importSleepFromHealthConnect() for the matching
    // separate permission launcher.
    val SLEEP_PERMISSIONS = setOf(
        HealthPermission.getReadPermission(SleepSessionRecord::class)
    )

    fun isAvailable(context: Context): Boolean =
        try {
            HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE
        } catch (_: Exception) {
            false
        }

    suspend fun hasAllPermissions(context: Context): Boolean {
        if (!isAvailable(context)) return false
        return try {
            val granted = HealthConnectClient.getOrCreate(context)
                .permissionController.getGrantedPermissions()
            granted.containsAll(PERMISSIONS)
        } catch (_: Exception) {
            false
        }
    }

    suspend fun hasSleepPermissions(context: Context): Boolean {
        if (!isAvailable(context)) return false
        return try {
            val granted = HealthConnectClient.getOrCreate(context)
                .permissionController.getGrantedPermissions()
            granted.containsAll(SLEEP_PERMISSIONS)
        } catch (_: Exception) {
            false
        }
    }

    /** Fetches exercise sessions from the last [days] days, with duration/calories/heart rate joined in. */
    suspend fun fetchRecentExerciseSessions(context: Context, days: Int = 7): List<ExternalActivitySample> {
        if (!isAvailable(context)) return emptyList()
        val client = HealthConnectClient.getOrCreate(context)
        val end = Instant.now()
        val start = end.minus(days.toLong(), ChronoUnit.DAYS)
        val range = TimeRangeFilter.between(start, end)

        val sessions = try {
            client.readRecords(ReadRecordsRequest(ExerciseSessionRecord::class, timeRangeFilter = range)).records
        } catch (_: Exception) {
            return emptyList()
        }

        return sessions.map { session ->
            val durationMin = Duration.between(session.startTime, session.endTime).toMillis() / 60000.0
            val sessionRange = TimeRangeFilter.between(session.startTime, session.endTime)

            val calories = try {
                client.readRecords(ReadRecordsRequest(TotalCaloriesBurnedRecord::class, timeRangeFilter = sessionRange))
                    .records.sumOf { it.energy.inKilocalories }
                    .takeIf { it > 0.0 }
            } catch (_: Exception) { null }

            val avgHeartRate = try {
                val bpmSamples = client.readRecords(ReadRecordsRequest(HeartRateRecord::class, timeRangeFilter = sessionRange))
                    .records.flatMap { it.samples }.map { it.beatsPerMinute.toDouble() }
                if (bpmSamples.isEmpty()) null else bpmSamples.average()
            } catch (_: Exception) { null }

            ExternalActivitySample(
                timestampMs = System.currentTimeMillis(),
                activityType = mapExerciseType(session.exerciseType, session.title),
                timeOfDayMs = session.startTime.toEpochMilli(),
                durationMin = durationMin,
                calories = calories,
                avgHeartRate = avgHeartRate,
                // Every Health Connect record carries a stable UUID assigned
                // by the platform at write time — used for import dedup.
                externalId = session.metadata.id
            )
        }
    }

    /**
     * Fetches sleep sessions from the last [days] days. Unlike exercise
     * sessions, Health Connect already models sleep as one record per night
     * (with a `stages` list inside it) — no manual grouping needed the way
     * iOS's HealthKit sleep-analysis samples require (HealthKit hands back a
     * flat list of per-stage samples with no session object at all).
     */
    suspend fun fetchRecentSleepSessions(context: Context, days: Int = 14): List<SleepSample> {
        if (!isAvailable(context)) return emptyList()
        val client = HealthConnectClient.getOrCreate(context)
        val end = Instant.now()
        val start = end.minus(days.toLong(), ChronoUnit.DAYS)
        val range = TimeRangeFilter.between(start, end)

        val sessions = try {
            client.readRecords(ReadRecordsRequest(SleepSessionRecord::class, timeRangeFilter = range)).records
        } catch (_: Exception) {
            return emptyList()
        }

        return sessions.map { session ->
            fun minutesOf(vararg stageTypes: Int): Double =
                session.stages
                    .filter { it.stage in stageTypes }
                    .sumOf { Duration.between(it.startTime, it.endTime).toMillis() / 60000.0 }

            val awakeMin = minutesOf(SleepSessionRecord.STAGE_TYPE_AWAKE, SleepSessionRecord.STAGE_TYPE_AWAKE_IN_BED)
            val lightMin = minutesOf(SleepSessionRecord.STAGE_TYPE_LIGHT)
            val deepMin = minutesOf(SleepSessionRecord.STAGE_TYPE_DEEP)
            val remMin = minutesOf(SleepSessionRecord.STAGE_TYPE_REM)
            val unspecifiedMin = minutesOf(SleepSessionRecord.STAGE_TYPE_SLEEPING, SleepSessionRecord.STAGE_TYPE_UNKNOWN)
            val totalSleepMin = lightMin + deepMin + remMin + unspecifiedMin
            // Full session span rather than summing non-awake stages, so this
            // matches iOS's definition exactly (and still works for sources
            // that report zero stage detail at all).
            val timeInBedMin = Duration.between(session.startTime, session.endTime).toMillis() / 60000.0

            SleepSample(
                timestampMs = System.currentTimeMillis(),
                provider = resolveProviderName(context, session.metadata.dataOrigin.packageName),
                sleepStartMs = session.startTime.toEpochMilli(),
                sleepEndMs = session.endTime.toEpochMilli(),
                timeInBedMin = timeInBedMin,
                totalSleepMin = totalSleepMin,
                lightMin = lightMin,
                deepMin = deepMin,
                remMin = remMin,
                awakeMin = awakeMin,
                unspecifiedMin = unspecifiedMin,
                // Every Health Connect record carries a stable UUID assigned
                // by the platform at write time — used for import dedup.
                externalId = session.metadata.id
            )
        }
    }

    /**
     * Health Connect only exposes the writing app's raw package name (e.g.
     * "com.garmin.android.apps.connectmobile") — not a friendly display name
     * the way HealthKit does on iOS. Resolves one via PackageManager, falling
     * back to the raw package name if the lookup fails (app not installed,
     * or hidden from us by Android's package-visibility rules) rather than
     * showing nothing.
     */
    private fun resolveProviderName(context: Context, packageName: String): String {
        if (packageName.isBlank()) return ""
        return try {
            val pm = context.packageManager
            val info = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(info).toString()
        } catch (_: Exception) {
            packageName
        }
    }

    /** Maps a Health Connect session onto this app's fixed activity-type list. */
    private fun mapExerciseType(type: Int, title: String?): String {
        val t = title?.lowercase().orEmpty()
        if (t.contains("run")) return "Running"
        if (t.contains("cycl") || t.contains("bik") || t.contains("ride")) return "Bike"
        if (t.contains("swim")) return "Swimming"
        if (t.contains("strength") || t.contains("weight")) return "Weight Training"
        if (t.contains("yoga") || t.contains("pilates") || t.contains("flexibility")) return "Pilates"

        // Fallback to the small set of numeric exercise-type constants that
        // have been stable since Health Connect's earliest releases.
        return when (type) {
            ExerciseSessionRecord.EXERCISE_TYPE_RUNNING,
            ExerciseSessionRecord.EXERCISE_TYPE_RUNNING_TREADMILL -> "Running"
            ExerciseSessionRecord.EXERCISE_TYPE_BIKING,
            ExerciseSessionRecord.EXERCISE_TYPE_BIKING_STATIONARY -> "Bike"
            ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_OPEN_WATER,
            ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_POOL -> "Swimming"
            ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING -> "Weight Training"
            ExerciseSessionRecord.EXERCISE_TYPE_YOGA -> "Pilates"
            else -> "Other"
        }
    }
}
