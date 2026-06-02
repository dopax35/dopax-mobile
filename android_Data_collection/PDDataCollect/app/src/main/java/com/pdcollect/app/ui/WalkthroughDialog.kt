package com.pdcollect.app.ui

import android.content.Context
import androidx.appcompat.app.AlertDialog
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.pdcollect.app.data.UserProfile

object WalkthroughDialog {

    fun showIfNeeded(context: Context) {
        val profile = UserProfile(context)
        if (profile.hasSeenWalkthrough) return

        val messages = listOf(
            "Welcome to the study! Here is a quick tour.",
            "1. Dashboard: See your tracking metrics and activity.\n\n2. Active Tests: Tap the 'Tests' button to perform your daily motor tests.\n\n3. Settings: You can pause data collection at any time by tapping the gear icon."
        )

        var currentIndex = 0
        lateinit var dialog: AlertDialog

        fun showCurrentMessage() {
            if (currentIndex >= messages.size) {
                profile.hasSeenWalkthrough = true
                dialog.dismiss()
                return
            }
            
            val isLast = currentIndex == messages.size - 1
            dialog = MaterialAlertDialogBuilder(context)
                .setTitle("Getting Started")
                .setMessage(messages[currentIndex])
                .setPositiveButton(if (isLast) "Got it" else "Next") { _, _ ->
                    currentIndex++
                    showCurrentMessage()
                }
                .setCancelable(false)
                .show()
        }

        showCurrentMessage()
    }
}
