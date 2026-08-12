package com.pdcollect.app.ui

import android.content.Intent
import android.os.Bundle
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

    private val signInLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val response = IdpResponse.fromResultIntent(result.data)

        if (result.resultCode == RESULT_OK) {
            val user = FirebaseAuth.getInstance().currentUser
            if (user != null) {
                checkCloudProfile()
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
            navigateNext()
            return
        }

        setContentView(R.layout.activity_welcome)

        findViewById<MaterialButton>(R.id.btnContinueGoogle).setOnClickListener {
            launchSignIn(listOf(AuthUI.IdpConfig.GoogleBuilder().build()))
        }
        findViewById<MaterialButton>(R.id.btnContinueEmail).setOnClickListener {
            launchSignIn(listOf(AuthUI.IdpConfig.EmailBuilder().build()))
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

    private fun checkCloudProfile() {
        lifecycleScope.launch {
            val profile = UserProfile(this@LoginActivity)
            val exists = FirebaseSyncManager.loadProfileFromCloud(profile)
            // Open a Postgres session when possible (additive; ignore failures).
            BackendSyncManager.ensureSession(this@LoginActivity, profile.userId)
            if (exists) {
                navigateNext()
            } else {
                startActivity(Intent(this@LoginActivity, ConsentActivity::class.java))
                finish()
            }
        }
    }

    private fun navigateNext() {
        val profile = UserProfile(this)
        if (!profile.consentGiven) {
            startActivity(Intent(this, ConsentActivity::class.java))
        } else if (!profile.profileComplete || profile.needsOnboardingV2) {
            startActivity(Intent(this, ProfileSetupActivity::class.java))
        } else {
            startActivity(Intent(this, MainActivity::class.java))
        }
        finish()
    }
}
