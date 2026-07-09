package com.pdcollect.app.logic

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.Date
import java.util.UUID

// ── Activity Categories (iOS ActivityCategory parity) ────────────────────────

enum class ActivityCategory(val rawValue: String) {
    TRANSITION("Transition"),
    EXERCISE("Exercise"),
    SLEEP("Sleep"),
    CUSTOM("Custom");

    companion object {
        fun from(raw: String): ActivityCategory =
            values().firstOrNull { it.rawValue.equals(raw, ignoreCase = true) } ?: CUSTOM
    }
}

// ── Activity Log Entry ────────────────────────────────────────────────────────

data class ActivityLogEntry(
    val id:           String  = UUID.randomUUID().toString(),
    val timestamp:    Date,
    val note:         String,
    val category:     ActivityCategory = ActivityCategory.CUSTOM,
    val mlPrediction: String? = null,
    val mlConfidence: Double? = null,
    val mlSource:     String? = null,
    val userLabel:    String? = null
) {
    fun toJSON(): JSONObject = JSONObject().apply {
        put("id",           id)
        put("timestamp",    timestamp.time)
        put("note",         note)
        put("category",     category.rawValue)
        mlPrediction?.let { put("mlPrediction", it) }
        mlConfidence?.let { put("mlConfidence", it) }
        mlSource?.let     { put("mlSource",     it) }
        userLabel?.let    { put("userLabel",    it) }
    }

    companion object {
        fun fromJSON(json: JSONObject): ActivityLogEntry? = try {
            ActivityLogEntry(
                id           = json.optString("id",  UUID.randomUUID().toString()),
                timestamp    = Date(json.getLong("timestamp")),
                note         = json.getString("note"),
                category     = ActivityCategory.from(json.optString("category", "Custom")),
                mlPrediction = json.optString("mlPrediction").takeIf { it.isNotEmpty() },
                mlConfidence = if (json.has("mlConfidence")) json.getDouble("mlConfidence") else null,
                mlSource     = json.optString("mlSource").takeIf { it.isNotEmpty() },
                userLabel    = json.optString("userLabel").takeIf { it.isNotEmpty() }
            )
        } catch (e: Exception) {
            Log.w("ActivityLogManager", "Failed to decode log entry: $e")
            null
        }
    }
}

// ── Activity Log Manager ──────────────────────────────────────────────────────

class ActivityLogManager private constructor(private val context: Context) {

    companion object {
        private const val TAG      = "ActivityLogManager"
        private const val FILENAME = "activity_logs.json"

        @Volatile private var instance: ActivityLogManager? = null
        fun getInstance(context: Context): ActivityLogManager =
            instance ?: synchronized(this) {
                instance ?: ActivityLogManager(context.applicationContext).also { instance = it }
            }
    }

    private val file get() = java.io.File(context.filesDir, FILENAME)
    private val logs = mutableListOf<ActivityLogEntry>()

    init { loadFromDisk() }

    // ── Public API ────────────────────────────────────────────────────────────

    /** All logs sorted oldest-first. */
    fun allLogs(): List<ActivityLogEntry> = synchronized(logs) { logs.toList() }

    fun addLog(
        note:         String,
        category:     ActivityCategory = ActivityCategory.CUSTOM,
        timestamp:    Date             = Date(),
        mlPrediction: String?          = null,
        mlConfidence: Double?          = null,
        mlSource:     String?          = null,
        userLabel:    String?          = null
    ) {
        val entry = ActivityLogEntry(
            timestamp    = timestamp,
            note         = note,
            category     = category,
            mlPrediction = mlPrediction,
            mlConfidence = mlConfidence,
            mlSource     = mlSource,
            userLabel    = userLabel
        )
        synchronized(logs) { logs.add(entry) }
        saveToDisk()
        Log.d(TAG, "Log added: \"$note\" (${category.rawValue}) " +
                "ml=$mlPrediction conf=${mlConfidence?.let { "%.3f".format(it) } ?: "null"} " +
                "src=$mlSource userLbl=$userLabel")
    }

    fun clearAll() {
        synchronized(logs) { logs.clear() }
        saveToDisk()
    }

    // ── Persistence ───────────────────────────────────────────────────────────

    private fun loadFromDisk() {
        try {
            if (!file.exists()) return
            val arr = JSONArray(file.readText())
            val loaded = (0 until arr.length())
                .mapNotNull { ActivityLogEntry.fromJSON(arr.getJSONObject(it)) }
                .sortedBy { it.timestamp }
            synchronized(logs) {
                logs.clear()
                logs.addAll(loaded)
            }
            Log.d(TAG, "Loaded ${logs.size} activity logs from disk")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load activity logs: $e")
        }
    }

    private fun saveToDisk() {
        try {
            val arr = JSONArray()
            synchronized(logs) { logs.forEach { arr.put(it.toJSON()) } }
            file.writeText(arr.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save activity logs: $e")
        }
    }
}
