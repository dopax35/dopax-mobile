package com.pdcollect.app.service

import android.content.Context

/**
 * Tracks which externally-imported workouts (Health Connect / Strava) have
 * already been written to physical_activity.csv, so re-importing the same
 * rolling look-back window — e.g. tapping "Import" again a few days later,
 * while the fetch window still overlaps the previous import — doesn't create
 * duplicate rows for the same workout.
 *
 * Keyed by "source:externalId" rather than just the raw ID, since each
 * source's IDs only make sense within that source's own ID space (a Health
 * Connect record UUID and a Strava numeric activity ID could theoretically
 * collide as raw strings).
 *
 * Deliberately NOT scoped to the current user profile / cleared on
 * Reset & Withdraw: a stale ID left behind from a previous participant on a
 * reused device is harmless (a new participant's own Strava/Health-Connect
 * account IDs are globally unique and will never collide with an old one),
 * so there's no correctness reason to wire this into that flow.
 */
object ImportedActivityStore {
    private const val PREFS = "imported_activity_ids"
    private const val KEY_IDS = "ids_csv"

    // Soft cap so this can't grow unbounded across years of daily imports.
    // Generously larger than any realistic number of workouts imported
    // across the fetch window's lifetime; trimming drops the oldest entries
    // first since they're stored in insertion order.
    private const val MAX_REMEMBERED = 2000

    @Synchronized
    fun isAlreadyImported(context: Context, source: String, externalId: String): Boolean {
        if (externalId.isBlank()) return false
        return loadIds(context).contains(key(source, externalId))
    }

    @Synchronized
    fun markImported(context: Context, source: String, externalId: String) {
        if (externalId.isBlank()) return
        val ids = loadIds(context).toMutableList()
        val k = key(source, externalId)
        if (ids.contains(k)) return
        ids.add(k)
        val trimmed = if (ids.size > MAX_REMEMBERED) ids.takeLast(MAX_REMEMBERED) else ids
        saveIds(context, trimmed)
    }

    private fun loadIds(context: Context): List<String> {
        val raw = prefs(context).getString(KEY_IDS, null)
        return if (raw.isNullOrEmpty()) emptyList() else raw.split("\n")
    }

    private fun saveIds(context: Context, ids: List<String>) {
        prefs(context).edit().putString(KEY_IDS, ids.joinToString("\n")).apply()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun key(source: String, externalId: String) = "$source:$externalId"
}
