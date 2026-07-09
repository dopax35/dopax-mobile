package com.pdcollect.app.logic

import android.annotation.SuppressLint
import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * MLPredictionStore — Android port of iOS MLPredictionStore.
 *
 * Disk-backed store of every "auto" inference result emitted by ActivityEngine.
 * Keyed by the window-end epoch second (same as iOS MLPredictionStore.record(at:)).
 *
 * Used by BleViewModel.buildCombinedCSV() to populate:
 *   ml_prediction, ml_confidence, ml_source="auto",
 *   ml_prob_running … ml_prob_stairs,
 *   ml_window_start_s, ml_window_end_s
 * — even when the user never tapped ✓ or ✗ on the inference strip.
 *
 * Priority in export (highest → lowest):
 *   1. User-confirmed entry  (mlSource == "confirmed") — model was right, user agreed.
 *   2. User-corrected entry  (mlSource == "corrected") — model was wrong, user fixed it.
 *   3. Auto store entry      (mlSource == "auto")      — raw engine output, no interaction.
 *   4. Empty                 — no prediction recorded near this epoch.
 *
 * Thread safety:
 *   All mutations are protected by a ReentrantLock.
 *   snapshot() returns a value-type Map copy — safe for the export IO coroutine.
 *   Disk writes run on a dedicated IO coroutine (debounced 3s).
 *
 * Lifecycle:
 *   clear() — called on explicit data wipe (clearHistory / erase).
 *   NOT cleared on BLE disconnect/reconnect — predictions must survive until export.
 *   iOS: "NOTE: MLPredictionStore is NOT cleared here. Clearing on every reconnect
 *         would delete auto-predictions captured during the previous session which
 *         are needed for export after a brief disconnect."
 *
 * File: ml_predictions.json (~260 KB for a 12h session at 1 inference / 10s).
 */
// Safe: we always receive and store applicationContext, never an Activity context.
// The singleton's context field cannot cause an Activity memory leak.
@SuppressLint("StaticFieldLeak")
class MLPredictionStore private constructor(private val context: Context) {

    // ── Entry (one inference result) ──────────────────────────────────────────

    data class Entry(
        /** Epoch second derived from windowEndMs. Used as dedup key and export lookup key. */
        val epochSec:      Long,
        val label:         String,
        val confidence:    Double,
        /** Full probability vector, index-aligned to ActivityEngine.labels:
         *  [Running, Walking, Sitting, Standing, Stairs]. Empty for legacy entries. */
        val probabilities: List<Double>,
        /** Epoch-ms of the FIRST IMU sample in the 250-sample window fed to the model.
         *  Corresponds to iOS windowStartEpoch (timeIntervalSince1970 of imuSamples250.first). */
        val windowStartMs: Long,
        /** Epoch-ms of the LAST IMU sample in the 250-sample window fed to the model.
         *  The dedup key is floor(windowEndMs / 1000) — matches iOS windowEndEpoch. */
        val windowEndMs:   Long
    ) {
        fun toJSON(): JSONObject = JSONObject().apply {
            put("epochSec",       epochSec)
            put("label",          label)
            put("confidence",     confidence)
            val arr = JSONArray(); probabilities.forEach { arr.put(it) }
            put("probabilities",  arr)
            put("windowStartMs",  windowStartMs)
            put("windowEndMs",    windowEndMs)
        }

        companion object {
            fun fromJSON(j: JSONObject): Entry? = try {
                val probArr = j.optJSONArray("probabilities")
                val probs   = if (probArr != null)
                    (0 until probArr.length()).map { probArr.getDouble(it) }
                else emptyList()
                Entry(
                    epochSec      = j.getLong("epochSec"),
                    label         = j.getString("label"),
                    confidence    = j.getDouble("confidence"),
                    probabilities = probs,
                    windowStartMs = j.optLong("windowStartMs", 0L),
                    windowEndMs   = j.optLong("windowEndMs",   0L)
                )
            } catch (e: Exception) {
                Log.w(TAG, "Failed to decode entry: $e"); null
            }
        }
    }

    // ── Singleton ─────────────────────────────────────────────────────────────

    companion object {
        private const val TAG      = "MLPredictionStore"
        private const val FILENAME = "ml_predictions.json"

        @Volatile private var instance: MLPredictionStore? = null
        fun getInstance(context: Context): MLPredictionStore =
            instance ?: synchronized(this) {
                instance ?: MLPredictionStore(context.applicationContext).also { instance = it }
            }
    }

    // ── In-memory store ───────────────────────────────────────────────────────

    private val file: File get() = File(context.filesDir, FILENAME)
    private val lock = ReentrantLock()

    // Main array + O(1) epoch-second dedup index (mirrors iOS epochIndex dict).
    private val entries    = mutableListOf<Entry>()
    private val epochIndex = HashMap<Long, Int>()   // epochSec → index in entries

    // ── Background IO ─────────────────────────────────────────────────────────

    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var saveJob: Job? = null

    init { loadFromDisk() }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Record one inference result.
     *
     * Deduplicates by window-end epoch second — later write wins, which matches
     * the iOS "higher confidence at that second" behaviour since later inference
     * calls on the same epoch represent fresher data.
     *
     * Keyed by windowEndMs/1000L (the end of the 250-sample IMU window) so the
     * epoch aligns with the temp row the export will look this entry up against.
     * iOS: keyed by windowEndEpoch = floor(imuSamples250.last.time.timeIntervalSince1970).
     *
     * Called from ActivityEngine.updateResults() on the IO thread.
     */
    fun record(
        label:           String,
        confidence:      Double,
        probabilities:   List<Double>,
        windowStartMs:   Long,
        windowEndMs:     Long
    ) {
        val epochSec = windowEndMs / 1000L
        val entry = Entry(epochSec, label, confidence, probabilities, windowStartMs, windowEndMs)
        lock.withLock {
            val idx = epochIndex[epochSec]
            if (idx != null) {
                entries[idx] = entry          // overwrite same-second — keep latest
            } else {
                epochIndex[epochSec] = entries.size
                entries.add(entry)
            }
        }
        scheduleSave()
    }

    /**
     * Snapshot for CSV export — returns a value-type Map safe for any thread.
     * iOS: MLPredictionStore.shared.snapshot() → [Int64: Entry]
     *
     * Keyed by epochSec for O(1) lookup in the temp-row loop.
     */
    fun snapshot(): Map<Long, Entry> {
        lock.withLock {
            val map = HashMap<Long, Entry>(entries.size * 2)
            for (e in entries) map[e.epochSec] = e
            return map
        }
    }

    /**
     * Clear all predictions and delete the disk file.
     *
     * Call on: explicit data wipe (clearHistory / erase).
     * Do NOT call on BLE disconnect — predictions must survive for export.
     * iOS: "NOT called on disconnect — predictions must survive until export."
     */
    fun clear() {
        lock.withLock {
            entries.clear()
            epochIndex.clear()
            saveJob?.cancel()
            saveJob = null
        }
        ioScope.launch {
            try {
                if (file.exists()) file.delete()
                Log.d(TAG, "Cleared and deleted $FILENAME")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete $FILENAME: $e")
            }
        }
    }

    /**
     * Returns entries whose window falls within the given local calendar date
     * ("yyyy-MM-dd"), JSON-encoded (same array shape as the on-disk file), or
     * null if there are none for that date.
     *
     * ml_predictions.json itself lives at context.filesDir — outside the
     * per-date directory tree that DataManager.zipDateData()/zipYesterdayData()
     * walk — so without this, every auto-inference result (full probability
     * vector + window bounds, not just the top-1 label/confidence already in
     * beanie_temperature.csv) would accumulate forever but never leave the
     * device. Called from DataManager's zip builders to add a per-date
     * "ml_predictions.json" entry alongside the CSVs.
     */
    fun entriesForDateAsJSON(dateStr: String): String? {
        val date = try {
            java.time.LocalDate.parse(dateStr)
        } catch (e: Exception) {
            Log.w(TAG, "entriesForDateAsJSON: bad date '$dateStr'"); return null
        }
        val zoneId = java.time.ZoneId.systemDefault()
        val startSec = date.atStartOfDay(zoneId).toEpochSecond()
        val endSec = date.plusDays(1).atStartOfDay(zoneId).toEpochSecond()

        val matches = lock.withLock {
            entries.filter { it.epochSec in startSec until endSec }.sortedBy { it.epochSec }
        }
        if (matches.isEmpty()) return null

        val arr = JSONArray()
        matches.forEach { arr.put(it.toJSON()) }
        return arr.toString()
    }

    /**
     * Force immediate disk write — call before an export to ensure latest
     * inference results are flushed to disk before the file is read.
     */
    @Suppress("unused")
    fun flush() {
        saveJob?.cancel()
        val snap = lock.withLock { entries.toList() }
        ioScope.launch { saveToDisk(snap) }
    }

    // ── Disk I/O ──────────────────────────────────────────────────────────────

    private fun loadFromDisk() {
        try {
            if (!file.exists()) return
            val arr    = JSONArray(file.readText())
            val loaded = (0 until arr.length())
                .mapNotNull { Entry.fromJSON(arr.getJSONObject(it)) }
            lock.withLock {
                entries.clear(); epochIndex.clear()
                entries.addAll(loaded)
                loaded.forEachIndexed { i, e -> epochIndex[e.epochSec] = i }
            }
            Log.d(TAG, "Loaded ${loaded.size} entries from $FILENAME")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load $FILENAME: $e")
        }
    }

    private fun scheduleSave() {
        saveJob?.cancel()
        val snap = lock.withLock { entries.toList() }
        saveJob = ioScope.launch {
            delay(3_000L)     // 3s debounce — same as iOS debounceSec
            saveToDisk(snap)
        }
    }

    private fun saveToDisk(snap: List<Entry>) {
        try {
            val arr = JSONArray()
            snap.forEach { arr.put(it.toJSON()) }
            file.writeText(arr.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save $FILENAME: $e")
        }
    }
}