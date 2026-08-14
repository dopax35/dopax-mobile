package com.pdcollect.app.ui

import android.content.Intent
import android.os.Bundle
import android.os.CountDownTimer
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.widget.EditText
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.material.button.MaterialButton
import com.google.firebase.auth.FirebaseAuth
import com.pdcollect.app.R
import com.pdcollect.app.data.BackendSyncManager
import com.pdcollect.app.data.EmailCodeStartResult
import com.pdcollect.app.data.EmailCodeVerifyInvalidReason
import com.pdcollect.app.data.EmailCodeVerifyResult

class EmailCodeActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_EMAIL = "email"
        const val EXTRA_RESEND_COOLDOWN = "resend_cooldown_seconds"
    }

    private lateinit var email: String
    private lateinit var hiddenCodeEdit: EditText
    private lateinit var codeBoxes: List<TextView>
    private lateinit var verifyButton: MaterialButton
    private lateinit var resendButton: MaterialButton
    private lateinit var countdownView: TextView
    private lateinit var errorView: TextView

    private var countDownTimer: CountDownTimer? = null
    private var secondsUntilResend = 0
    private var isVerifying = false
    private var isResending = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_email_code)

        email = intent.getStringExtra(EXTRA_EMAIL).orEmpty()
        if (email.isBlank()) {
            finish()
            return
        }

        secondsUntilResend = intent.getIntExtra(EXTRA_RESEND_COOLDOWN, 60)

        hiddenCodeEdit = findViewById(R.id.editHiddenCode)
        verifyButton = findViewById(R.id.btnVerify)
        resendButton = findViewById(R.id.btnResend)
        countdownView = findViewById(R.id.tvResendCountdown)
        errorView = findViewById(R.id.tvError)
        codeBoxes = listOf(
            findViewById(R.id.codeBox0),
            findViewById(R.id.codeBox1),
            findViewById(R.id.codeBox2),
            findViewById(R.id.codeBox3),
            findViewById(R.id.codeBox4),
            findViewById(R.id.codeBox5),
        )

        findViewById<TextView>(R.id.tvEmailSubtitle).text = "Sent to $email"
        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { finish() }

        findViewById<LinearLayout>(R.id.codeBoxesRow).setOnClickListener {
            hiddenCodeEdit.requestFocus()
            showKeyboard(hiddenCodeEdit)
        }
        findViewById<View>(R.id.codeEntryContainer).setOnClickListener {
            hiddenCodeEdit.requestFocus()
            showKeyboard(hiddenCodeEdit)
        }

        hiddenCodeEdit.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                val digits = s?.toString()?.filter { it.isDigit() }?.take(6).orEmpty()
                if (digits != s?.toString()) {
                    hiddenCodeEdit.setText(digits)
                    hiddenCodeEdit.setSelection(digits.length)
                    return
                }
                errorView.visibility = View.GONE
                renderCodeBoxes(digits)
                verifyButton.isEnabled = digits.length == 6 && !isVerifying
                if (digits.length == 6 && !isVerifying) {
                    verifyCode(digits)
                }
            }
        })

        verifyButton.setOnClickListener {
            verifyCode(hiddenCodeEdit.text?.toString().orEmpty())
        }

        resendButton.setOnClickListener { resendCode() }

        startResendCountdown(secondsUntilResend)
        hiddenCodeEdit.post {
            hiddenCodeEdit.requestFocus()
            showKeyboard(hiddenCodeEdit)
        }
    }

    override fun onDestroy() {
        countDownTimer?.cancel()
        countDownTimer = null
        super.onDestroy()
    }

    private fun renderCodeBoxes(code: String) {
        for (index in codeBoxes.indices) {
            val box = codeBoxes[index]
            box.text = code.getOrNull(index)?.toString().orEmpty()
            box.setBackgroundResource(
                if (index == code.length && code.length < 6) {
                    R.drawable.bg_onboarding_code_box_focused
                } else {
                    R.drawable.bg_onboarding_code_box
                },
            )
        }
    }

    private fun startResendCountdown(seconds: Int) {
        countDownTimer?.cancel()
        secondsUntilResend = seconds.coerceAtLeast(0)
        updateResendUi()

        if (secondsUntilResend <= 0) return

        countDownTimer = object : CountDownTimer(secondsUntilResend * 1000L, 1000L) {
            override fun onTick(millisUntilFinished: Long) {
                secondsUntilResend = (millisUntilFinished / 1000L).toInt()
                updateResendUi()
            }

            override fun onFinish() {
                secondsUntilResend = 0
                updateResendUi()
            }
        }.also { it.start() }
    }

    private fun updateResendUi() {
        val canResend = secondsUntilResend <= 0 && !isResending
        resendButton.isEnabled = canResend
        resendButton.setTextColor(
            ContextCompat.getColor(
                this,
                if (canResend) R.color.onboarding_accent else R.color.gray_50,
            ),
        )
        countdownView.text = if (secondsUntilResend <= 0) {
            "Resend code"
        } else {
            val minutes = secondsUntilResend / 60
            val seconds = secondsUntilResend % 60
            String.format(java.util.Locale.US, "Resend code (in %d:%02d)", minutes, seconds)
        }
    }

    private fun verifyCode(code: String) {
        if (code.length != 6 || isVerifying) return
        isVerifying = true
        errorView.visibility = View.GONE
        verifyButton.isEnabled = false

        BackendSyncManager.verifyEmailCode(this, email, code) { result ->
            when (result) {
                is EmailCodeVerifyResult.Success -> {
                    FirebaseAuth.getInstance()
                        .signInWithCustomToken(result.customToken)
                        .addOnCompleteListener { task ->
                            isVerifying = false
                            if (task.isSuccessful) {
                                LoginActivity.checkCloudProfile(this)
                            } else {
                                showError(task.exception?.localizedMessage ?: "Sign-in failed.")
                                verifyButton.isEnabled = hiddenCodeEdit.text?.length == 6
                            }
                        }
                }
                is EmailCodeVerifyResult.InvalidCode -> {
                    isVerifying = false
                    verifyButton.isEnabled = hiddenCodeEdit.text?.length == 6
                    showError(invalidCodeMessage(result.reason, result.attemptsRemaining))
                }
                EmailCodeVerifyResult.SignInUnavailable -> {
                    isVerifying = false
                    verifyButton.isEnabled = hiddenCodeEdit.text?.length == 6
                    showError("Sign-in is temporarily unavailable.")
                }
                EmailCodeVerifyResult.NetworkError -> {
                    isVerifying = false
                    verifyButton.isEnabled = hiddenCodeEdit.text?.length == 6
                    showError("Something went wrong. Please try again.")
                }
            }
        }
    }

    private fun resendCode() {
        if (secondsUntilResend > 0 || isResending) return
        isResending = true
        errorView.visibility = View.GONE
        resendButton.isEnabled = false

        BackendSyncManager.startEmailCode(this, email) { result ->
            isResending = false
            when (result) {
                is EmailCodeStartResult.Sent -> {
                    hiddenCodeEdit.setText("")
                    renderCodeBoxes("")
                    verifyButton.isEnabled = false
                    startResendCountdown(result.resendCooldownSeconds)
                    hiddenCodeEdit.requestFocus()
                    showKeyboard(hiddenCodeEdit)
                }
                is EmailCodeStartResult.TooManyRequests -> {
                    startResendCountdown(result.retryAfterSeconds)
                    showError("Too many attempts. Try again in ${result.retryAfterSeconds} seconds.")
                }
                EmailCodeStartResult.EmailDeliveryFailed ->
                    showError("We couldn't send the code. Please try again later.")
                else -> showError("Something went wrong. Please try again.")
            }
            updateResendUi()
        }
    }

    private fun invalidCodeMessage(
        reason: EmailCodeVerifyInvalidReason,
        attemptsRemaining: Int?,
    ): String = when (reason) {
        EmailCodeVerifyInvalidReason.NO_ACTIVE_CODE -> "No active code. Request a new one."
        EmailCodeVerifyInvalidReason.EXPIRED -> "That code expired. Request a new one."
        EmailCodeVerifyInvalidReason.TOO_MANY_ATTEMPTS -> "Too many wrong attempts. Request a new code."
        EmailCodeVerifyInvalidReason.MISMATCH -> {
            if (attemptsRemaining != null) {
                "That code isn't right. $attemptsRemaining attempts left."
            } else {
                "That code isn't right."
            }
        }
    }

    private fun showError(message: String) {
        errorView.text = message
        errorView.visibility = View.VISIBLE
    }

    private fun showKeyboard(view: View) {
        val imm = getSystemService(INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
        imm.showSoftInput(view, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
    }
}
