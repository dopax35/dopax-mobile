package com.pdcollect.app.ui

import android.content.Intent
import android.os.Bundle
import android.util.Patterns
import android.view.View
import android.widget.EditText
import android.widget.ImageButton
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.widget.doAfterTextChanged
import com.google.android.material.button.MaterialButton
import com.pdcollect.app.R
import com.pdcollect.app.data.BackendSyncManager
import com.pdcollect.app.data.EmailCodeStartResult

class EmailSignInActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_email_sign_in)

        val emailEdit = findViewById<EditText>(R.id.editEmail)
        val sendButton = findViewById<MaterialButton>(R.id.btnSendCode)
        val errorView = findViewById<TextView>(R.id.tvError)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { finish() }

        emailEdit.doAfterTextChanged {
            errorView.visibility = View.GONE
            val address = it?.toString()?.trim().orEmpty()
            sendButton.isEnabled = Patterns.EMAIL_ADDRESS.matcher(address).matches()
        }

        sendButton.setOnClickListener {
            val address = emailEdit.text?.toString()?.trim().orEmpty()
            if (!Patterns.EMAIL_ADDRESS.matcher(address).matches()) return@setOnClickListener

            errorView.visibility = View.GONE
            sendButton.isEnabled = false

            BackendSyncManager.startEmailCode(this, address) { result ->
                sendButton.isEnabled = Patterns.EMAIL_ADDRESS.matcher(address).matches()
                when (result) {
                    is EmailCodeStartResult.Sent -> {
                        startActivity(
                            Intent(this, EmailCodeActivity::class.java)
                                .putExtra(EmailCodeActivity.EXTRA_EMAIL, address)
                                .putExtra(
                                    EmailCodeActivity.EXTRA_RESEND_COOLDOWN,
                                    result.resendCooldownSeconds,
                                ),
                        )
                    }
                    EmailCodeStartResult.InvalidRequest ->
                        showError(errorView, "Please enter a valid email address.")
                    is EmailCodeStartResult.TooManyRequests ->
                        showError(errorView, "Too many attempts. Try again in ${result.retryAfterSeconds} seconds.")
                    EmailCodeStartResult.EmailDeliveryFailed ->
                        showError(errorView, "We couldn't send the code. Please try again later.")
                    EmailCodeStartResult.NetworkError ->
                        showError(errorView, "Something went wrong. Please try again.")
                }
            }
        }
    }

    private fun showError(errorView: TextView, message: String) {
        errorView.text = message
        errorView.visibility = View.VISIBLE
    }
}
