package com.pdcollect.app.service

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.pdcollect.app.data.model.ExternalActivitySample
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
