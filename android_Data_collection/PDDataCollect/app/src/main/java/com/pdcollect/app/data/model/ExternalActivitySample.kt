package com.pdcollect.app.data.model

/**
 * A single workout/activity imported from a connected fitness source
 * (Health Connect or Strava), normalized to the same shape regardless of
 * where it came from so it can be written straight into physical_activity.csv.
 */
data class ExternalActivitySample(
    val timestampMs: Long,     // when the import happened
    val activityType: String,  // mapped onto Constants.PHYSICAL_ACTIVITY_TYPES
    val timeOfDayMs: Long,     // workout start time
    val durationMin: Double,
    val calories: Double?,
    val avgHeartRate: Double?,
    // Stable per-source identifier (Health Connect record UUID / Strava
    // activity ID) used only to skip re-importing the same workout on a
    // later import — never written to the CSV. Blank if a source ever
    // fails to supply one, which ImportedActivityStore treats as "can't
    // dedupe this one, always import" rather than silently dropping it.
    val externalId: String
)
