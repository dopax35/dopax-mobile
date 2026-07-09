import Foundation

/// Swift port of Android's PostureState.kt — 9 states matching the reference
/// PostureEngine.swift exactly. No posture history/charts UI reads this today
/// (out of scope per product decision), but BeaniePostureEngine computes it for
/// parity with Android and so it's available if a future screen needs it.
enum PostureState: String {
    case upright     = "Great"
    case mildBad     = "Good"
    case poor        = "Poor"
    case headBack    = "Head back"
    case moving      = "Moving"
    // Lying states (v5 axis-frame calibration only) — detected when the
    // dominant gravity displacement axis is >= 0.6 in magnitude, i.e. the
    // head/beanie is near-horizontal.
    case lyingBack   = "Lying back"
    case lyingFront  = "Lying front"
    case lyingSide   = "Lying side"
    case unknown     = "--"

    var label: String { rawValue }
}
