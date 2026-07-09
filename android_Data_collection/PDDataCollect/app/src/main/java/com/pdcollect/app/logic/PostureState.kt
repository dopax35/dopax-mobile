package com.pdcollect.app.logic

// PostureState — uses Int color instead of Compose Color to avoid Compose dependency.
// iOS PostureState parity — 9 states matching PostureEngine.swift exactly.
// lyingBack / lyingFront / lyingSide are detected in PostureEngine.classifyWithFrame()
// when the total gravity displacement magnitude is ≥ 0.6 (device near-horizontal).
enum class PostureState(val label: String, val colorInt: Int) {
    UPRIGHT("Great",        0xFF1D9E75.toInt()),
    MILD_BAD("Good",        0xFFE88C30.toInt()),
    POOR("Poor",            0xFFE24B4A.toInt()),
    HEAD_BACK("Head back",  0xFFC97B20.toInt()),
    MOVING("Moving",        0xFF757575.toInt()),
    // ── Lying states (v5 axis-frame only) ────────────────────────────────────
    // Detected when the dominant gravity displacement axis is ≥ 0.6 in magnitude,
    // indicating the head/beanie is near-horizontal (lying down).
    LYING_BACK("Lying back",   0xFF5B8FD4.toInt()),   // face-up: dominant back axis
    LYING_FRONT("Lying front", 0xFF4A7ABF.toInt()),   // face-down: dominant fwd axis
    LYING_SIDE("Lying side",   0xFF6A9FD8.toInt()),   // sideways: dominant lat axis
    UNKNOWN("--",           0xFF9E9E9E.toInt())
}
