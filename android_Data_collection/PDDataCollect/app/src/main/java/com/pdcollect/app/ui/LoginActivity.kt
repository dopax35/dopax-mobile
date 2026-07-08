package com.pdcollect.app.ui

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.firebase.ui.auth.AuthUI
import com.firebase.ui.auth.IdpResponse
import com.google.firebase.auth.FirebaseAuth
import com.pdcollect.app.data.FirebaseSyncManager
import com.pdcollect.app.data.UserProfile
import kotlinx.coroutines.launch

class LoginActivity : AppCompatActivity() {

    private val signInLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val response = IdpResponse.fromResultIntent(result.data)

        if (result.resultCode == RESULT_OK) {
            // Successfully signed in
            val user = FirebaseAuth.getInstance().currentUser
            if (user != null) {
                checkCloudProfile()
            }
        } else {
            // Sign in failed
            if (response == null) {
                // User pressed back button
                Toast.makeText(this, "Sign in cancelled", Toast.LENGTH_SHORT).show()
                finish()
            } else {
                val errorMsg = "Sign in failed: ${response.error?.errorCode} - ${response.error?.message}"
                android.util.Log.e("LoginActivity", errorMsg, response.error)
                // This activity has no layout of its own (FirebaseUI's screen is the
                // UI); if we don't finish() here, a failed sign-in leaves the user
                // stranded on a blank screen with no visible way to retry. Closing
                // lets them reopen the app, which restarts the sign-in flow — same
                // recovery path as the "user cancelled" branch above.
                Toast.makeText(
                    this,
                    "Sign in didn't go through. Please check your internet connection and reopen the app to try again.",
                    Toast.LENGTH_LONG
                ).show()
                finish()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val auth = FirebaseAuth.getInstance()
        if (auth.currentUser != null) {
            // Already signed in
            navigateNext()
        } else {
            // Choose authentication providers
            val providers = arrayListOf(
                AuthUI.IdpConfig.EmailBuilder().build(),
                AuthUI.IdpConfig.PhoneBuilder().build(),
                AuthUI.IdpConfig.GoogleBuilder().build()
            )

            // Create and launch sign-in intent
            val signInIntent = AuthUI.getInstance()
                .createSignInIntentBuilder()
                .setAvailableProviders(providers)
                .setIsSmartLockEnabled(false)
                .build()
            signInLauncher.launch(signInIntent)
        }
    }

    private fun checkCloudProfile() {
        lifecycleScope.launch {
            val profile = UserProfile(this@LoginActivity)
            val exists = FirebaseSyncManager.loadProfileFromCloud(profile)
            if (exists) {
                // The user has a profile in the cloud, so they are reinstalling
                navigateNext()
            } else {
                // No profile in the cloud, proceed to consent
                startActivity(Intent(this@LoginActivity, ConsentActivity::class.java))
                finish()
            }
        }
    }

    private fun navigateNext() {
        val profile = UserProfile(this)
        if (!profile.consentGiven) {
            startActivity(Intent(this, ConsentActivity::class.java))
        } else if (!profile.profileComplete) {
            startActivity(Intent(this, ProfileSetupActivity::class.java))
        } else {
            startActivity(Intent(this, MainActivity::class.java))
        }
        finish()
    }
}
