package com.pdcollect.app.data.model

/**
 * A sleep session imported from a connected health source (Health Connect —
 * which in turn surfaces Garmin Connect, Samsung Health, Fitbit, etc.,
 * whatever the user has syncing into it). Matches iOS's sleep.csv format
 * exactly.
 */
data class SleepSample(
    val timestampMs: Long,       // when the import happened
    val provider: String,        // app that recorded the night, e.g. "Garmin Connect" — blank if unresolvable
    val sleepStartMs: Long,
    val sleepEndMs: Long,
    val timeInBedMin: Double,
    val totalSleepMin: Double,
    val lightMin: Double,
    val deepMin: Double,
    val remMin: Double,
    val awakeMin: Double,
    val unspecifiedMin: Double,
    // Stable per-source identifier (Health Connect record UUID) used only to
    // skip re-importing the same night on a later import — never written to
    // the CSV. Blank if a source ever fails to supply one, which
    // ImportedActivityStore treats as "can't dedupe this one, always
    // import" rather than silently dropping it.
    val externalId: String
)
