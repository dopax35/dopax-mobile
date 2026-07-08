package com.pdcollect.app.util

import android.content.Context
import androidx.appcompat.app.AlertDialog
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import kotlin.random.Random

object NudgeGenerator {

    fun showNudgeAfterTest(context: Context, testName: String, onDismiss: () -> Unit = {}) {
        val genericMessages = listOf(
            "Great job completing the $testName!",
            "Keep up the good work! Consistent tracking helps research.",
            "You're making great progress in your daily tests.",
            "Every test you complete brings us one step closer to better insights!"
        )

        val specificMessages = when (testName) {
            "Hand Turning Test" -> listOf(
                "Your supination and pronation movements are looking steady today.",
                "Good rhythm on the hand turning! Consistent pacing is key.",
                "Hand turning complete. Be sure to rest your wrist if needed."
            )
            "Finger Tapping Test" -> listOf(
                "Great tapping speed today!",
                "Your finger agility is looking good. Keep it up!",
                "Nice and steady rhythm on the finger taps."
            )
            "Trail Making Test" -> listOf(
                "Way to stay focused on the trail!",
                "Good cognitive speed and visual attention.",
                "Trail completed smoothly. Excellent concentration!"
            )
            "Spiral Tracing Test" -> listOf(
                "Good motor control on the spiral tracing.",
                "Your drawing hand seems steady today.",
                "Nice tracing! Precision is what counts here."
            )
            "Leg Agility Test" -> listOf(
                "Great lower body coordination today!",
                "Your leg agility is looking strong.",
                "Good pacing with your foot taps."
            )
            else -> emptyList()
        }

        val allMessages = genericMessages + specificMessages
        val randomMessage = allMessages[Random.nextInt(allMessages.size)]

        MaterialAlertDialogBuilder(context)
            .setTitle("Test Complete")
            .setMessage(randomMessage)
            .setPositiveButton("Awesome!") { dialog, _ ->
                dialog.dismiss()
            }
            .setOnDismissListener { onDismiss() }
            .show()
    }
}
