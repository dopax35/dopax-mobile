package com.pdcollect.app.logic

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.Date

/**
 * ActivityPrediction — mirrors iOS struct ActivityPrediction.
 */
data class ActivityPrediction(
    val label:      String,
    val category:   ActivityCategory = ActivityCategory.EXERCISE,
    val confidence: Double,
    val startedAt:  Date = Date()
)

/**
 * ActivityInferenceManager — iOS ActivityInferenceManager parity.
 *
 * Manages the ✓/✗ inference strip lifecycle.
 */
object ActivityInferenceManager {

    private val _pending = MutableStateFlow<ActivityPrediction?>(null)
    val pending: StateFlow<ActivityPrediction?> = _pending.asStateFlow()

    // ── Prediction lifecycle ──────────────────────────────────────────────────

    fun setPrediction(label: String, confidence: Double) {
        _pending.value = ActivityPrediction(
            label      = label,
            category   = categoryFor(label),
            confidence = confidence.coerceIn(0.0, 1.0),
            startedAt  = Date()
        )
    }

    fun confirmPrediction(context: Context) {
        val pred = _pending.value ?: return
        _pending.value = null

        ActivityLogManager.getInstance(context).addLog(
            note         = pred.label,
            category     = pred.category,
            timestamp    = pred.startedAt,
            mlPrediction = pred.label,
            mlConfidence = pred.confidence,
            mlSource     = "confirmed",
            userLabel    = pred.label
        )

        ActivityEngine.getInstance(context).resetLastPushedActivity()
    }

    fun correctPrediction(
        context:           Context,
        correctedLabel:    String,
        correctedCategory: ActivityCategory = ActivityCategory.CUSTOM
    ) {
        val pred = _pending.value ?: return
        _pending.value = null

        val mgr = ActivityLogManager.getInstance(context)

        mgr.addLog(
            note         = correctedLabel,
            category     = correctedCategory,
            timestamp    = pred.startedAt,
            mlPrediction = pred.label,
            mlConfidence = pred.confidence,
            mlSource     = "corrected",
            userLabel    = correctedLabel
        )

        mgr.addLog(
            note      = "[ML correction] predicted: ${pred.label} → actual: $correctedLabel",
            category  = ActivityCategory.CUSTOM,
            timestamp = Date(pred.startedAt.time + 1000L)
        )

        ActivityEngine.getInstance(context).resetLastPushedActivity()
    }

    fun dismissPrediction() { _pending.value = null }

    fun clearPending() { _pending.value = null }

    private fun categoryFor(label: String): ActivityCategory = when (label) {
        "Running", "Walking", "Stairs" -> ActivityCategory.EXERCISE
        "Sitting", "Standing"          -> ActivityCategory.CUSTOM
        else                           -> ActivityCategory.CUSTOM
    }
}
