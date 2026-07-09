package com.pdcollect.app.ui

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import com.pdcollect.app.service.StravaManager

/**
 * Transparent catcher for the "pdcollect://strava-callback" redirect Strava
 * sends back after the user approves access in their browser/Custom Tab.
 * Kept as its own tiny, exported activity so MainActivity itself doesn't
 * need to become exported just to receive this one deep link.
 */
class StravaAuthCallbackActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val handled = intent?.data?.let { StravaManager.handleAuthRedirect(this, it) } ?: false
        Toast.makeText(
            this,
            if (handled) "Strava connected." else "Strava connection failed — please try again.",
            Toast.LENGTH_LONG
        ).show()
        startActivity(
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        )
        finish()
    }
}
