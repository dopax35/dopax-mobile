package com.pdcollect.app.ui

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import com.pdcollect.app.service.StravaManager
import kotlinx.coroutines.launch

/**
 * Transparent catcher for the "pdcollect://strava-callback" redirect Strava
 * sends back after the user approves access in their browser/Custom Tab.
 * Kept as its own tiny, exported activity so MainActivity itself doesn't
 * need to become exported just to receive this one deep link.
 *
 * Extends ComponentActivity (not plain Activity, as this used to) so
 * lifecycleScope is available — StravaManager.handleAuthRedirect() does a
 * real network call and must run as a suspend function on a coroutine, not
 * synchronously on the main thread the way this activity used to call it,
 * which would throw NetworkOnMainThreadException on every single use.
 * ComponentActivity rather than AppCompatActivity specifically: it already
 * provides lifecycleScope with no theme requirements, so the manifest's
 * existing plain-platform Theme.Translucent.NoTitleBar can stay as-is —
 * AppCompatActivity would crash on that theme
 * ("You need to use a Theme.AppCompat theme... with this activity").
 */
class StravaAuthCallbackActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uri = intent?.data
        if (uri == null) {
            finishToMainActivity()
            return
        }
        lifecycleScope.launch {
            // null = success; non-null = a human-readable reason, since a
            // "code" query param being present doesn't by itself mean the
            // token exchange that follows actually succeeded.
            val error = StravaManager.handleAuthRedirect(this@StravaAuthCallbackActivity, uri)
            Toast.makeText(
                this@StravaAuthCallbackActivity,
                error ?: "Strava connected.",
                Toast.LENGTH_LONG
            ).show()
            finishToMainActivity()
        }
    }

    private fun finishToMainActivity() {
        startActivity(
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        )
        finish()
    }
}
