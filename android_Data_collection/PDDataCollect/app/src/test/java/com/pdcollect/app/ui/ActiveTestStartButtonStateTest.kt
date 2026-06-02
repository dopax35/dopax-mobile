package com.pdcollect.app.ui

import android.content.pm.ActivityInfo
import android.view.View
import android.widget.Button
import android.widget.TextView
import com.pdcollect.app.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
@LooperMode(LooperMode.Mode.PAUSED)
class ActiveTestStartButtonStateTest {

    @Test
    fun fingerTapping_showsDisabledRunningStateAfterCountdown() {
        val controller = Robolectric.buildActivity(FingerTappingActivity::class.java).setup()
        val activity = controller.get()
        try {
            activity.findViewById<Button>(R.id.btnStartTapping).performClick()

            val statusButton = activity.findViewById<Button>(R.id.btnStartTappingStatus)
            assertEquals(View.VISIBLE, statusButton.visibility)
            assertDisabledButton(statusButton, "Starting...")

            invokePrivateNoArg(activity, "startActualTest")

            assertDisabledButton(statusButton, "Test Running")
        } finally {
            controller.pause().stop().destroy()
        }
    }

    @Test
    fun handTurning_showsDisabledRunningStateAfterCountdown() {
        val controller = Robolectric.buildActivity(HandTurningActivity::class.java).setup()
        val activity = controller.get()
        try {
            val startButton = activity.findViewById<Button>(R.id.btnStartTurning)
            startButton.performClick()
            assertDisabledButton(startButton, "Starting...")

            invokePrivateNoArg(activity, "startRecording")

            assertDisabledButton(startButton, "Test Running")
        } finally {
            controller.pause().stop().destroy()
        }
    }

    @Test
    fun handTurning_stopRecordingUpdatesUiWithoutCrashing() {
        val controller = Robolectric.buildActivity(HandTurningActivity::class.java).setup()
        val activity = controller.get()
        try {
            activity.findViewById<Button>(R.id.btnStartTurning).performClick()
            invokePrivateNoArg(activity, "startRecording")
            invokePrivateNoArg(activity, "stopRecording")

            val timerText = activity.findViewById<TextView>(R.id.tvTimer)
            assertEquals("Done!", timerText.text.toString())
        } finally {
            controller.pause().stop().destroy()
        }
    }

    @Test
    fun handTurning_locksOrientationToPreventRotationRestart() {
        val controller = Robolectric.buildActivity(HandTurningActivity::class.java).setup()
        val activity = controller.get()
        try {
            assertEquals(ActivityInfo.SCREEN_ORIENTATION_LOCKED, activity.requestedOrientation)
        } finally {
            controller.pause().stop().destroy()
        }
    }

    @Test
    fun legAgility_showsDisabledRunningStateAfterCountdown() {
        val controller = Robolectric.buildActivity(LegAgilityActivity::class.java).setup()
        val activity = controller.get()
        try {
            val startButton = activity.findViewById<Button>(R.id.btnStartLeg)
            startButton.performClick()
            assertDisabledButton(startButton, "Starting...")

            invokePrivateNoArg(activity, "startRecording")

            assertDisabledButton(startButton, "Test Running")
        } finally {
            controller.pause().stop().destroy()
        }
    }

    @Test
    fun legAgility_stopRecordingUpdatesUiWithoutCrashing() {
        val controller = Robolectric.buildActivity(LegAgilityActivity::class.java).setup()
        val activity = controller.get()
        try {
            activity.findViewById<Button>(R.id.btnStartLeg).performClick()
            invokePrivateNoArg(activity, "startRecording")
            invokePrivateNoArg(activity, "stopRecording")

            val timerText = activity.findViewById<TextView>(R.id.tvTimer)
            assertEquals("Done!", timerText.text.toString())
        } finally {
            controller.pause().stop().destroy()
        }
    }

    @Test
    fun trailMaking_disablesStartButtonWhileTestIsRunning() {
        val controller = Robolectric.buildActivity(TrailMakingTestActivity::class.java).setup()
        val activity = controller.get()
        try {
            val startButton = activity.findViewById<Button>(R.id.btnStartTmt)
            startButton.performClick()

            assertDisabledButton(startButton, "Test Running")
        } finally {
            controller.pause().stop().destroy()
        }
    }

    private fun assertDisabledButton(button: Button, expectedLabel: String) {
        assertFalse(button.isEnabled)
        assertFalse(button.isClickable)
        assertEquals(expectedLabel, button.text.toString())
        assertEquals(0.45f, button.alpha, 0.001f)
    }

    private fun invokePrivateNoArg(target: Any, methodName: String) {
        val method = target::class.java.getDeclaredMethod(methodName)
        method.isAccessible = true
        method.invoke(target)
    }
}
