package com.pdcollect.app.service

import android.inputmethodservice.InputMethodService
import android.inputmethodservice.Keyboard
import android.inputmethodservice.KeyboardView
import android.media.AudioManager
import android.text.InputType
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.inputmethod.EditorInfo
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.data.model.KeyEvent
import com.pdcollect.app.util.TimeUtils

/**
 * PDKeyboardService — bilingual (Hebrew / English) InputMethodService, plus a
 * numbers/symbols page.
 *
 * Privacy: only key *class* and word-length metadata are logged. The actual
 * characters typed are committed to the host app's InputConnection and never
 * written to our data store. Password fields are silently skipped.
 *
 * Layouts
 *   • English QWERTY  → res/xml/qwerty.xml   (long-press keys for digits/accents)
 *   • Hebrew          → res/xml/hebrew.xml   (long-press keys for digits)
 *   • Numbers/symbols → res/xml/numbers.xml
 *
 * Convenience features (added July 2026 — the previous bare-bones layout had
 * no numbers page at all and no correction shortcuts, which made everyday
 * typing painful, especially for users with tremor who pay a high cost per
 * extra tap):
 *   • Long-press a top-row letter for its digit / an accented variant.
 *   • Swipe left anywhere on the keyboard to delete the whole previous word,
 *     instead of repeated backspace taps.
 *   • Double-tap space for ". " + auto-capitalize the next letter.
 *   • Auto-capitalize at the start of a field and after ./!/?.
 *   • Haptic + click-sound feedback on every key so a registered tap is never
 *     in doubt.
 *
 * Language toggle: press the "עA / EN" key in the bottom row.
 * The 🌐 globe key (KEYCODE_MODE_CHANGE) hands control to the Android
 * input-method picker so users can switch to any other keyboard.
 */
class PDKeyboardService : InputMethodService(), KeyboardView.OnKeyboardActionListener {

    // ── Modes ────────────────────────────────────────────────────────────────
    private enum class Mode { LETTERS_EN, LETTERS_HE, NUMBERS }

    // ── UI ────────────────────────────────────────────────────────────────────
    private lateinit var keyboardView: KeyboardView
    private lateinit var englishKeyboard: Keyboard
    private lateinit var hebrewKeyboard: Keyboard
    private lateinit var numbersKeyboard: Keyboard

    // ── State ─────────────────────────────────────────────────────────────────
    private var mode               = Mode.LETTERS_EN
    private var previousLetterMode = Mode.LETTERS_EN
    private var isCaps         = false
    private var autoCapNext    = true   // capitalize the first letter of a fresh field
    private var currentWordLen = 0
    private var targetApp      = ""
    private var lastSpaceTimeMs = 0L

    // Custom keycodes defined in our XML layouts
    companion object {
        /** Switches the layout between English and Hebrew within this keyboard. */
        const val KEYCODE_LANG_TOGGLE = -100
        /** Switches to/from the numbers & symbols page. */
        const val KEYCODE_NUMBERS_TOGGLE = -101
        /** Max time between two space taps to be treated as "double space" (ms). */
        const val DOUBLE_SPACE_WINDOW_MS = 600L
    }

    // ── Data ──────────────────────────────────────────────────────────────────
    private lateinit var profile:     UserProfile
    private lateinit var dataManager: DataManager
    private val audioManager by lazy { getSystemService(AUDIO_SERVICE) as AudioManager }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        profile     = UserProfile(this)
        dataManager = DataManager(this, profile)
    }

    override fun onCreateInputView(): View {
        keyboardView    = layoutInflater.inflate(R.layout.keyboard_view, null) as KeyboardView
        englishKeyboard = Keyboard(this, R.xml.qwerty)
        hebrewKeyboard  = Keyboard(this, R.xml.hebrew)
        numbersKeyboard = Keyboard(this, R.xml.numbers)
        applyCurrentKeyboard()
        keyboardView.setOnKeyboardActionListener(this)
        keyboardView.isPreviewEnabled = true
        keyboardView.isHapticFeedbackEnabled = true
        return keyboardView
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        targetApp      = info?.packageName ?: "unknown"
        currentWordLen = 0
        autoCapNext    = true
        lastSpaceTimeMs = 0L
        // Never land on the numbers page when a fresh field opens — go back
        // to whichever language keyboard was last used for typing.
        if (mode == Mode.NUMBERS) mode = previousLetterMode
        applyCurrentKeyboard()
        updateShiftVisual()
    }

    override fun onDestroy() {
        dataManager.closeAll()
        super.onDestroy()
    }

    // ── Layout helpers ────────────────────────────────────────────────────────

    private fun applyCurrentKeyboard() {
        keyboardView.keyboard = when (mode) {
            Mode.LETTERS_EN -> englishKeyboard
            Mode.LETTERS_HE -> hebrewKeyboard
            Mode.NUMBERS    -> numbersKeyboard
        }
        keyboardView.invalidateAllKeys()
    }

    private fun toggleLanguage() {
        mode   = if (mode == Mode.LETTERS_HE) Mode.LETTERS_EN else Mode.LETTERS_HE
        isCaps = false
        applyCurrentKeyboard()
        updateShiftVisual()
    }

    private fun toggleNumbers() {
        if (mode == Mode.NUMBERS) {
            mode = previousLetterMode
        } else {
            previousLetterMode = mode
            mode = Mode.NUMBERS
        }
        applyCurrentKeyboard()
        // Refreshes englishKeyboard's cached shifted/label state in case
        // autoCapNext changed while the numbers page was showing (typing a
        // digit resets it) — otherwise the letter keys could come back
        // showing stale case when the user returns from numbers.
        updateShiftVisual()
    }

    /**
     * Keeps the rendered key case in sync with both the manual shift toggle
     * and auto-capitalization — previously only the manual shift key updated
     * this, so autoCapNext could silently commit an uppercase letter while
     * every key still visually showed lowercase. Also mutates each letter
     * key's label directly, since Android's classic KeyboardView does not
     * auto-flip key label case from Keyboard.isShifted the way a hand-built
     * key view (like the iOS side) naturally does.
     */
    private fun updateShiftVisual() {
        if (mode == Mode.NUMBERS) return

        if (mode == Mode.LETTERS_HE) {
            // Hebrew has no letter case — isCaps can't even be toggled here
            // (hebrew.xml has no shift key), so this is just a defensive
            // no-op guard against running the English label-flip logic
            // against Hebrew's non-Latin key codes.
            if (hebrewKeyboard.isShifted != isCaps) {
                hebrewKeyboard.isShifted = isCaps
                keyboardView.invalidateAllKeys()
            }
            return
        }

        val shifted = isCaps || autoCapNext
        if (englishKeyboard.isShifted == shifted) return
        englishKeyboard.isShifted = shifted
        for (key in englishKeyboard.keys) {
            val code = key.codes?.getOrNull(0) ?: continue
            if (code in 'a'.code..'z'.code) {
                key.label = if (shifted) key.label.toString().uppercase() else key.label.toString().lowercase()
            }
        }
        keyboardView.invalidateAllKeys()
    }

    // ── KeyboardView.OnKeyboardActionListener ─────────────────────────────────

    override fun onKey(primaryCode: Int, keyCodes: IntArray?) {
        val ic = currentInputConnection ?: return
        val timestamp = TimeUtils.currentTimeMs()
        var keyClass  = "other"
        var isBack    = false

        when (primaryCode) {

            Keyboard.KEYCODE_DELETE -> {
                isBack   = true
                keyClass = "backspace"
                ic.deleteSurroundingText(1, 0)
                if (currentWordLen > 0) currentWordLen--
            }

            Keyboard.KEYCODE_SHIFT -> {
                if (autoCapNext) {
                    // Explicit shift while auto-cap is pending overrides it,
                    // so the user can force a lowercase letter where
                    // auto-cap would otherwise have capitalized (e.g. typing
                    // a deliberately lowercase word at a sentence start).
                    autoCapNext = false
                    isCaps      = false
                } else {
                    isCaps = !isCaps
                }
            }

            // Handle input-method picker (globe / mode change)
            Keyboard.KEYCODE_MODE_CHANGE -> {
                val imm = getSystemService(INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
                imm.showInputMethodPicker()
            }

            KEYCODE_LANG_TOGGLE    -> toggleLanguage()
            KEYCODE_NUMBERS_TOGGLE -> toggleNumbers()

            // Enter / Done
            10, Keyboard.KEYCODE_DONE -> {
                flushWordLength()
                val actionId = currentInputEditorInfo?.actionId ?: 0
                if (actionId != 0) ic.performEditorAction(actionId)
                else               ic.commitText("\n", 1)
                keyClass    = "enter"
                autoCapNext = true
            }

            // Space (with double-space → ". " convenience)
            32 -> {
                val textBefore = ic.getTextBeforeCursor(1, 0)?.toString()
                val elapsed    = timestamp - lastSpaceTimeMs
                if (textBefore == " " && lastSpaceTimeMs != 0L && elapsed in 1..DOUBLE_SPACE_WINDOW_MS) {
                    ic.deleteSurroundingText(1, 0)
                    ic.commitText(". ", 1)
                    autoCapNext = true
                    keyClass    = "auto_period"
                } else {
                    flushWordLength()
                    ic.commitText(" ", 1)
                    keyClass = "space"
                }
                lastSpaceTimeMs = timestamp
            }

            else -> {
                if (primaryCode > 0) {
                    val raw           = primaryCode.toChar()
                    val isHebrew      = mode == Mode.LETTERS_HE
                    val wasManualCaps = isCaps
                    val useUpper      = raw.isLetter() && !isHebrew && (isCaps || autoCapNext)
                    val char          = if (useUpper) raw.uppercaseChar() else raw
                    ic.commitText(char.toString(), 1)
                    keyClass = KeyEvent.classify(char)
                    if (keyClass == "char" || keyClass == "digit") {
                        currentWordLen++
                        autoCapNext = false
                    }
                    if (char == '.' || char == '!' || char == '?') {
                        autoCapNext = true
                    }
                    // A one-shot shift auto-cancels after a single letter, like
                    // every mainstream keyboard — holding Caps stays sticky only
                    // via the explicit shift toggle above.
                    if (wasManualCaps && raw.isLetter() && !isHebrew) {
                        isCaps = false
                    }
                }
                lastSpaceTimeMs = 0L
            }
        }

        updateShiftVisual()
        logIfAllowed(timestamp, keyClass, isBack)
    }

    /** Swipe left anywhere on the keyboard deletes the previous word in one gesture. */
    override fun swipeLeft() {
        val ic = currentInputConnection ?: return
        val before = ic.getTextBeforeCursor(64, 0)?.toString()
        if (before.isNullOrEmpty()) return

        var idx = before.length
        while (idx > 0 && before[idx - 1].isWhitespace()) idx--
        while (idx > 0 && !before[idx - 1].isWhitespace()) idx--
        val deleteCount = before.length - idx
        if (deleteCount > 0) {
            ic.deleteSurroundingText(deleteCount, 0)
            currentWordLen = 0
            logIfAllowed(TimeUtils.currentTimeMs(), "swipe_delete_word", true)
        }
    }

    // ── Word-length flush ─────────────────────────────────────────────────────

    private fun flushWordLength() {
        if (currentWordLen > 0) {
            logIfAllowed(TimeUtils.currentTimeMs(), "word_len_$currentWordLen", false)
            currentWordLen = 0
        }
    }

    // ── Logging ───────────────────────────────────────────────────────────────

    private fun logIfAllowed(timestamp: Long, keyClass: String, isBackspace: Boolean) {
        if (!profile.keyloggingEnabled) return

        // Never log characters typed in password fields
        val inputType = currentInputEditorInfo?.inputType ?: 0
        val variation = inputType and InputType.TYPE_MASK_VARIATION
        val isPassword = variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
        if (isPassword) return

        try {
            val event = KeyEvent(
                timestampMs = timestamp,
                keyClass    = keyClass,
                isBackspace = isBackspace,
                sourceApp   = targetApp
            )
            dataManager.writeKeyEvent(event.toCsvRow())
        } catch (_: Exception) { /* best-effort */ }
    }

    // ── Feedback ──────────────────────────────────────────────────────────────

    override fun onPress(primaryCode: Int) {
        keyboardView.performHapticFeedback(
            HapticFeedbackConstants.KEYBOARD_TAP,
            HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING
        )
        try {
            audioManager.playSoundEffect(AudioManager.FX_KEYPRESS_STANDARD, -1f)
        } catch (_: Exception) { /* best-effort; some devices/policies block this */ }
    }

    // ── Unused callbacks ──────────────────────────────────────────────────────
    override fun onRelease(primaryCode: Int) {}
    override fun onText(text: CharSequence?) {}
    override fun swipeRight() {}
    override fun swipeDown()  {}
    override fun swipeUp()    {}
}
