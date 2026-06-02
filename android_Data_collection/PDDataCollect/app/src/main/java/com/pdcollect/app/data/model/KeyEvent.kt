package com.pdcollect.app.data.model

/**
 * A redacted keystroke record. We deliberately do NOT log the literal text the
 * participant typed — that would capture passwords, private messages, banking
 * info, etc. from any app on the device. Instead we record:
 *
 *   - timestamp (for inter-key interval / typing rhythm features)
 *   - keyClass: one of "char", "digit", "space", "punct", "backspace",
 *               "enter", "other" — enough for tremor/bradykinesia analysis
 *   - sourceApp: package that owned the input field
 *
 * `keyText` is kept in the data class for compatibility but is always written
 * as a redacted token, never the raw character.
 */
data class KeyEvent(
    val timestampMs: Long,
    val keyClass: String,
    val isBackspace: Boolean,
    val sourceApp: String
) {
    fun toCsvRow(): String = "$timestampMs,$keyClass,$isBackspace,$sourceApp"

    companion object {
        /** Map an arbitrary character to a non-identifying category. */
        fun classify(ch: Char): String = when {
            ch == '\b' || ch == '\u0008' -> "backspace"
            ch == '\n' || ch == '\r' -> "enter"
            ch == ' ' -> "space"
            ch.isDigit() -> "digit"
            ch.isLetter() -> "char"
            else -> "punct"
        }
    }
}
