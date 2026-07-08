package com.pdcollect.app.service

import android.inputmethodservice.InputMethodService
import android.inputmethodservice.Keyboard
import android.inputmethodservice.KeyboardView
import android.text.InputType
import android.view.View
import android.view.inputmethod.EditorInfo
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.data.model.KeyEvent
import com.pdcollect.app.util.TimeUtils

/**
 * PDKeyboardService — bilingual (Hebrew / English) InputMethodService.
 *
 * Privacy: only key *class* and word-length metadata are logged. The actual
 * characters typed are committed to the host app's InputConnection and never
 * written to our data store. Password fields are silently skipped.
 *
 * Layouts
 *   • English QWERTY  → res/xml/qwerty.xml
 *   • Hebrew          → res/xml/hebrew.xml
 *
 * Language toggle: press the "עA / EN" key in the bottom row.
 * The toggle cycles between Hebrew and English within this keyboard.
 * The 🌐 globe key (KEYCODE_MODE_CHANGE) hands control to the Android
 * input-method picker so users can switch to any other keyboard.
 */
class PDKeyboardService : InputMethodService(), KeyboardView.OnKeyboardActionListener {

    // ── UI ────────────────────────────────────────────────────────────────────
    private lateinit var keyboardView: KeyboardView
    private lateinit var englishKeyboard: Keyboard
    private lateinit var hebrewKeyboard: Keyboard

    // ── State ─────────────────────────────────────────────────────────────────
    private var isHebrew       = false
    private var isCaps         = false
    private var currentWordLen = 0
    private var targetApp      = ""

    // Custom keycodes defined in our XML layouts
    companion object {
        /** Switches the layout between English and Hebrew within this keyboard. */
        const val KEYCODE_LANG_TOGGLE = -100
    }

    // ── Data ──────────────────────────────────────────────────────────────────
    private lateinit var profile:     UserProfile
    private lateinit var dataManager: DataManager

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        profile     = UserProfile(this)
        dataManager = DataManager(this, profile)
    }

    override fun onCreateInputView(): View {
        keyboardView  = layoutInflater.inflate(R.layout.keyboard_view, null) as KeyboardView
        englishKeyboard = Keyboard(this, R.xml.qwerty)
        hebrewKeyboard  = Keyboard(this, R.xml.hebrew)
        applyCurrentKeyboard()
        keyboardView.setOnKeyboardActionListener(this)
        keyboardView.isPreviewEnabled = true
        return keyboardView
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        targetApp      = info?.packageName ?: "unknown"
        currentWordLen = 0
        applyCurrentKeyboard()
    }

    override fun onDestroy() {
        dataManager.closeAll()
        super.onDestroy()
    }

    // ── Layout helpers ────────────────────────────────────────────────────────

    private fun applyCurrentKeyboard() {
        keyboardView.keyboard = if (isHebrew) hebrewKeyboard else englishKeyboard
        keyboardView.invalidateAllKeys()
    }

    private fun toggleLanguage() {
        isHebrew = !isHebrew
        isCaps   = false
        applyCurrentKeyboard()
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
                isCaps = !isCaps
                val kb = if (isHebrew) hebrewKeyboard else englishKeyboard
                kb.isShifted = isCaps
                keyboardView.invalidateAllKeys()
            }

            // Handle input-method picker (globe / mode change)
            Keyboard.KEYCODE_MODE_CHANGE -> {
                // Ask Android to show the input-method picker
                val imm = getSystemService(INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
                imm.showInputMethodPicker()
            }

            KEYCODE_LANG_TOGGLE -> toggleLanguage()

            // Enter / Done
            10, Keyboard.KEYCODE_DONE -> {
                flushWordLength()
                val actionId = currentInputEditorInfo?.actionId ?: 0
                if (actionId != 0) ic.performEditorAction(actionId)
                else               ic.commitText("\n", 1)
                keyClass = "enter"
            }

            // Space
            32 -> {
                flushWordLength()
                ic.commitText(" ", 1)
                keyClass = "space"
            }

            else -> {
                if (primaryCode > 0) {
                    val raw  = primaryCode.toChar()
                    val char = if (raw.isLetter() && isCaps && !isHebrew) raw.uppercaseChar() else raw
                    ic.commitText(char.toString(), 1)
                    keyClass = KeyEvent.classify(char)
                    if (keyClass == "char" || keyClass == "digit") currentWordLen++
                }
            }
        }

        logIfAllowed(timestamp, keyClass, isBack)
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

    // ── Unused callbacks ──────────────────────────────────────────────────────
    override fun onPress(primaryCode: Int)   {}
    override fun onRelease(primaryCode: Int) {}
    override fun onText(text: CharSequence?) {}
    override fun swipeLeft()  {}
    override fun swipeRight() {}
    override fun swipeDown()  {}
    override fun swipeUp()    {}
}
