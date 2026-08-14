package com.pdcollect.app.ui

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.firebase.ui.auth.AuthUI
import com.firebase.ui.auth.IdpResponse
import com.google.android.material.button.MaterialButton
import com.google.firebase.auth.FirebaseAuth
import com.pdcollect.app.R
import com.pdcollect.app.data.BackendSyncManager
import com.pdcollect.app.data.FirebaseSyncManager
import com.pdcollect.app.data.UserProfile
import kotlinx.coroutines.launch

/**
 * Welcome / auth entry. Visual shell matches Figma onboarding Welcome;
 * providers and post-auth routing are unchanged (Email / Phone / Google →
 * Consent / ProfileSetup / Main).
 */
class LoginActivity : AppCompatActivity() {

    companion object {
        fun checkCloudProfile(activity: AppCompatActivity) {
            activity.lifecycleScope.launch {
                val profile = UserProfile(activity)
                val exists = FirebaseSyncManager.loadProfileFromCloud(profile)
                BackendSyncManager.ensureSession(activity, profile.userId)
                if (exists) {
                    navigateNext(activity)
                } else {
                    activity.startActivity(Intent(activity, ConsentActivity::class.java))
                    activity.finish()
                }
            }
        }

        fun navigateNext(activity: AppCompatActivity) {
            val profile = UserProfile(activity)
            val target = when {
                !profile.consentGiven -> ConsentActivity::class.java
                !profile.profileComplete || profile.needsOnboardingV2 -> ProfileSetupActivity::class.java
                else -> MainActivity::class.java
            }
            activity.startActivity(Intent(activity, target))
            activity.finish()
        }
    }

    private val signInLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val response = IdpResponse.fromResultIntent(result.data)

        if (result.resultCode == RESULT_OK) {
            val user = FirebaseAuth.getInstance().currentUser
            if (user != null) {
                checkCloudProfile(this)
            }
        } else {
            if (response == null) {
                Toast.makeText(this, "Sign in cancelled", Toast.LENGTH_SHORT).show()
            } else {
                val errorMsg = "Sign in failed: ${response.error?.errorCode} - ${response.error?.message}"
                android.util.Log.e("LoginActivity", errorMsg, response.error)
                Toast.makeText(
                    this,
                    "Sign in didn't go through. Please check your internet connection and try again.",
                    Toast.LENGTH_LONG
                ).show()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val auth = FirebaseAuth.getInstance()
        if (auth.currentUser != null) {
            navigateNext(this)
            return
        }

        setContentView(R.layout.activity_welcome)

        val emailLink = findViewById<TextView>(R.id.btnContinueEmail)
        emailLink.visibility = View.GONE
        BackendSyncManager.fetchEmailCodeConfig(this) { enabled ->
            emailLink.visibility = if (enabled) View.VISIBLE else View.GONE
        }

        findViewById<MaterialButton>(R.id.btnContinueGoogle).setOnClickListener {
            launchSignIn(listOf(AuthUI.IdpConfig.GoogleBuilder().build()))
        }
        emailLink.setOnClickListener {
            startActivity(Intent(this, EmailSignInActivity::class.java))
        }
        findViewById<TextView>(R.id.btnPhoneSignIn).setOnClickListener {
            launchSignIn(listOf(AuthUI.IdpConfig.PhoneBuilder().build()))
        }
    }

    private fun launchSignIn(providers: List<AuthUI.IdpConfig>) {
        val signInIntent = AuthUI.getInstance()
            .createSignInIntentBuilder()
            .setAvailableProviders(providers)
            .setIsSmartLockEnabled(false)
            .setTheme(R.style.Theme_PDDataCollect)
            .build()
        signInLauncher.launch(signInIntent)
    }
}
