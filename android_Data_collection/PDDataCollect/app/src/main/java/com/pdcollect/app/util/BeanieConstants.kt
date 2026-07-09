@file:Suppress("unused")
package com.pdcollect.app.util


/**--------------------------------------------------------------------------------------
 * Centralized constants so thresholds don't get duplicated across views / BLE logic.
 * This is the Kotlin equivalent of the BeanieConstants enum from the Swift project.
 *
 * UPDATED: Improved environment detection thresholds to reduce false positives
 * Synced with iOS BeanieConstants.swift
--------------------------------------------------------------------------------------*/
object BeanieConstants
{
    // region Units / physics
    /** q = k * ΔT  where k is in kcal/(K·s) */
    const val HEAT_FLUX_KCAL_PER_K_PER_SEC: Double = 0.02   // iOS parity: 0.02 kcal/(K·s)
    // endregion

    // region Live status thresholds (C)
    const val LOW_SKIN_THRESHOLD_C: Double = 33.5   // iOS parity: 33.5°C
    const val HIGH_SKIN_THRESHOLD_C: Double = 35.5  // iOS parity: 35.5°C
    // endregion

    // region Rapid change gating
    /** Threshold for "rapid change" detection (°C/min) in the live pipeline. */
    const val RAPID_CHANGE_C_PER_MINUTE_THRESHOLD_LIVE: Double = 4.0
    // endregion

    // region Sampling / averaging windows
    const val LIVE_CHART_WINDOW_HOURS: Double = 1.0

    const val PUT_ON_CONFIRM_SECONDS: Double = 12.0
    const val SUPPRESS_PUT_ON_AFTER_TAKEOFF_SECONDS: Double = 30.0
    const val SUPPRESS_PUT_ON_AFTER_CONNECT_SECONDS: Double = 20.0

    const val PUT_ON_WARMUP_SECONDS: Double = 90.0  // iOS parity: 90s

    /** For the first ~5–10 minutes after a put-on, the big dial should show a fast temperature. */
    const val FAST_DIAL_INSTANT_SECONDS_AFTER_PUT_ON: Double = 8.0 * 60.0

    /** Rolling average window for the stable dial. */
    const val STABLE_DIAL_WINDOW_SECONDS: Double = 300.0

    /** Minimum span required before we consider the 5-minute rolling average valid. */
    const val STABLE_DIAL_MIN_SPAN_SECONDS: Double = 240.0

    const val IGNORE_ENV_TRANSITIONS_AFTER_PUT_ON_SECONDS: Double = 180.0

    // region Environment inference thresholds (outer-led)
    // UPDATED: More conservative to prevent false positives from motion artifacts
    const val ENV_STABLE_SLOPE_MAX_C_PER_MIN: Double = 1.2
    const val ENV_STABLE_SLOPE_MAX_C_PER_SEC: Double = ENV_STABLE_SLOPE_MAX_C_PER_MIN / 60.0
    const val ENV_STABLE_MIN_DURATION_SECONDS: Double = 60.0

    // UPDATED: Require larger outer slope to trigger transition (was 1.6)
    const val ENV_TRANSITION_OUTER_SLOPE_MIN_C_PER_MIN: Double = 2.5
    const val ENV_TRANSITION_OUTER_SLOPE_MIN_C_PER_SEC: Double = ENV_TRANSITION_OUTER_SLOPE_MIN_C_PER_MIN / 60.0

    // UPDATED: Require larger net change over 60s (was 0.7)
    const val ENV_TRANSITION_NET_OUTER_CHANGE_60S_MIN_C: Double = 1.0

    // UPDATED: Require longer confirmation time (was 15)
    const val ENV_TRANSITION_CONFIRM_SECONDS: Double = 45.0

    // UPDATED: Require outer to dominate inner more strongly (was 1.3)
    const val ENV_TRANSITION_OUTER_DOMINANCE_RATIO_MIN: Double = 2.0

    // UPDATED: Hold transition state longer (was 90)
    const val ENV_TRANSITION_HOLD_SECONDS: Double = 120.0

    // region Wear detection tuning (Not Worn)
    // FIXED: Was 90.0 which caused 5+ minute delays in detecting not-worn state
    // iOS uses ~15 seconds for responsive takeoff detection
    const val NOT_WORN_ENTER_DEBOUNCE_SECONDS: Double = 15.0
    const val NOT_WORN_EXIT_DEBOUNCE_SECONDS: Double = 15.0
    const val NOT_WORN_COOL_MAX_C: Double = 31.0
    const val NOT_WORN_DELTA_ABS_MAX_C: Double = 0.35
    // endregion

    // region Heat flux smoothing
    const val HEAT_FLUX_EMA_TAU_SECONDS: Double = 20.0
    // endregion

    // region History chart binning
    const val HISTORY_MIN_ZOOM_SECONDS: Double = 60.0 * 60.0 // 60 min
    const val HISTORY_MAX_GAP_SECONDS:  Double = 30.0 * 60.0 // 30 min
    // endregion

    // region Absolute Environment Detection (NEW - synced from iOS)
    // These provide backup detection when rate-based detection fails
    // If outer temp is below this AND delta is large, we're definitely outside
    const val OUTER_TEMP_CLEARLY_OUTSIDE_MAX_C: Double = 24.0
    // If outer temp is above this AND delta is small, we're likely inside
    const val OUTER_TEMP_CLEARLY_INSIDE_MIN_C: Double = 28.0
    // Delta threshold for "clearly outside" detection
    const val DELTA_T_CLEARLY_OUTSIDE_MIN_C: Double = 3.0
    // Heat flux thresholds for absolute environment detection (cal/s)
    const val HEAT_FLUX_CLEARLY_OUTSIDE_MIN_CAL_PER_S: Double = 100.0
    const val HEAT_FLUX_CLEARLY_INSIDE_MAX_CAL_PER_S: Double = 55.0
    // endregion

    // region Motion Artifact Rejection (NEW - synced from iOS)
    // Cooldown after detecting a motion artifact before allowing env transitions
    const val MOTION_ARTIFACT_COOLDOWN_SECONDS: Double = 45.0
    // Maximum duration a motion artifact should last
    const val MOTION_ARTIFACT_MAX_DURATION_SECONDS: Double = 30.0
    // Both sensors must not move together faster than this for real transition
    const val MOTION_ARTIFACT_BOTH_SENSORS_SLOPE_C_PER_MIN: Double = 6.0
    // endregion

    // region Wet Beanie Detection (NEW - synced from iOS)
    // If inner temp is below this, the sensor may be wet or not making good contact
    const val MIN_PHYSIOLOGICAL_INNER_C: Double = 30.0
    // endregion

    // region Display Smoothing (NEW - synced from iOS)
    // Maximum rate of change for display temperature (prevents sudden jumps)
    const val DISPLAY_MAX_RATE_C_PER_MIN: Double = 3.0
    // Physiological bounds for display temperature
    const val DISPLAY_PHYS_LO: Double = 29.0
    const val DISPLAY_PHYS_HI: Double = 39.5
    // Post-display EMA smoothing time constant
    const val POST_DISPLAY_EMA_TAU_SECONDS: Double = 15.0
    // endregion

    // region Warmup Timing (NEW - synced from iOS)
    // Duration to hide temperature during initial warmup (phase 1)
    const val WARMUP_HIDE_SECONDS: Double = 90.0
    // Total warmup duration before showing averaged values (phase 2 ends)
    const val WARMUP_TOTAL_SECONDS: Double = 4.0 * 60.0  // 240 seconds
    // Maximum duration of thermalizing state
    const val MAX_THERMALIZING_DURATION_SECONDS: Double = 4.0 * 60.0  // 240 seconds
    // Delay before arming freeze detection after warmup complete
    const val FREEZE_ARM_DELAY_SECONDS: Double = 30.0
    // endregion

    // region Physiological Sanity Thresholds (NEW - synced from iOS)
    // Maximum physiologically possible skin temperature
    const val MAX_PHYSIOLOGICAL_TSKIN_C: Double = 38.5
    // Minimum physiologically possible skin temperature
    const val MIN_PHYSIOLOGICAL_TSKIN_C: Double = 34.0
    // Large delta T threshold indicating thermal transient
    const val LARGE_DELTA_T_THRESHOLD: Double = 4.0
    // Large outer change threshold requiring extended freeze
    const val LARGE_OUTER_CHANGE_THRESHOLD: Double = 5.0
    // endregion
}