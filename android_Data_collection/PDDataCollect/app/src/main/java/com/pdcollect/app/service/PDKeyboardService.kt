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

class PDKeyboardService : InputMethodService(), KeyboardView.OnKeyboardActionListener {
    private lateinit var keyboardView: KeyboardView
    private lateinit var keyboard: Keyboard
    private lateinit var dataManager: DataManager
    private lateinit var profile: UserProfile
    private var isCaps = false
    private var targetApp = ""

    override fun onCreate() {
        super.onCreate()
        profile = UserProfile(this)
        dataManager = DataManager(this, profile)
    }

    override fun onCreateInputView(): View {
        keyboardView = layoutInflater.inflate(R.layout.keyboard_view, null) as KeyboardView
        keyboard = Keyboard(this, R.xml.qwerty)
        keyboardView.keyboard = keyboard
        keyboardView.setOnKeyboardActionListener(this)
        return keyboardView
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        targetApp = info?.packageName ?: "unknown"
    }

    override fun onKey(primaryCode: Int, keyCodes: IntArray?) {
        val ic = currentInputConnection ?: return
        val timestamp = TimeUtils.currentTimeMs()
        var keyClass = "other"
        var isBackspace = false

        when (primaryCode) {
            Keyboard.KEYCODE_DELETE -> {
                isBackspace = true
                keyClass = "backspace"
                ic.deleteSurroundingText(1, 0)
            }
            Keyboard.KEYCODE_SHIFT -> {
                isCaps = !isCaps
                keyboard.isShifted = isCaps
                keyboardView.invalidateAllKeys()
            }
            Keyboard.KEYCODE_DONE, -4 -> { // -4 is ENTER
                val actionId = currentInputEditorInfo?.actionId ?: 0
                if (actionId != 0) {
                    ic.performEditorAction(actionId)
                } else {
                    ic.commitText("\n", 1)
                }
            }
            32 -> { // SPACE
                ic.commitText(" ", 1)
            }
            else -> {
                var code = primaryCode.toChar()
                if (Character.isLetter(code) && isCaps) {
                    code = code.uppercaseChar()
                }
                keyClass = com.pdcollect.app.data.model.KeyEvent.classify(code)
                ic.commitText(code.toString(), 1)
            }
        }

        if (profile.keyloggingEnabled) {
            val isPassword = currentInputEditorInfo?.inputType?.let { inputType ->
                val variation = inputType and InputType.TYPE_MASK_VARIATION
                variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
            } ?: false

            if (!isPassword) {
                val keyEvent = KeyEvent(
                    timestampMs = timestamp,
                    keyClass = keyClass,
                    isBackspace = isBackspace,
                    sourceApp = targetApp
                )
                dataManager.writeKeyEvent(keyEvent.toCsvRow())
            }
        }
    }

    override fun onPress(primaryCode: Int) {}
    override fun onRelease(primaryCode: Int) {}
    override fun onText(text: CharSequence?) {}
    override fun swipeLeft() {}
    override fun swipeRight() {}
    override fun swipeDown() {}
    override fun swipeUp() {}

    override fun onDestroy() {
        dataManager.closeAll()
        super.onDestroy()
    }
}
