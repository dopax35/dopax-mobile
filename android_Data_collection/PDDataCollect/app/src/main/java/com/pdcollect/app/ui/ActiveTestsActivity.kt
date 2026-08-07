package com.pdcollect.app.ui

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Button
import androidx.appcompat.app.AppCompatActivity
import com.pdcollect.app.R

class ActiveTestsActivity : AppCompatActivity() {

    private var launchedTestName: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_active_tests)

        findViewById<Button>(R.id.btnTmt).setOnClickListener {
            launchedTestName = "Trail Making Test"
            startActivity(Intent(this, TrailMakingTestActivity::class.java))
        }

        findViewById<Button>(R.id.btnVoice).setOnClickListener {
            launchedTestName = "Voice Sample Recording"
            startActivity(Intent(this, VoiceSampleActivity::class.java))
        }

        findViewById<Button>(R.id.btnVoiceTest).setOnClickListener {
            launchedTestName = "Voice Acoustic Test"
            startActivity(Intent(this, VoiceTestActivity::class.java))
        }

        findViewById<Button>(R.id.btnFingerTapping).setOnClickListener {
            launchedTestName = "Finger Tapping Test"
            startActivity(Intent(this, FingerTappingActivity::class.java))
        }

        findViewById<Button>(R.id.btnFingersTest).setOnClickListener {
            launchedTestName = "Free-Space Fingers Test"
            startActivity(Intent(this, FingersTestActivity::class.java))
        }

        findViewById<Button>(R.id.btnPronationSupination).setOnClickListener {
            launchedTestName = "Hand Turning Test"
            startActivity(Intent(this, HandTurningActivity::class.java))
        }

        findViewById<Button>(R.id.btnSpiralTracing).setOnClickListener {
            launchedTestName = "Spiral Tracing Test"
            startActivity(Intent(this, SpiralTracingActivity::class.java))
        }

        findViewById<Button>(R.id.btnLegAgility).setOnClickListener {
            launchedTestName = "Leg Agility Test"
            startActivity(Intent(this, LegAgilityActivity::class.java))
        }

        findViewById<Button>(R.id.btnFacialMovement).setOnClickListener {
            launchedTestName = "Facial Movement Test"
            startActivity(Intent(this, FacialMovementTestActivity::class.java))
        }

        findViewById<Button>(R.id.btnBack).setOnClickListener {
            finish()
        }
    }

    override fun onResume() {
        super.onResume()
        if (launchedTestName != null) {
            val testName = launchedTestName!!
            launchedTestName = null

            Handler(Looper.getMainLooper()).postDelayed({
                if (!isFinishing && !isDestroyed) {
                    com.pdcollect.app.util.NudgeGenerator.showNudgeAfterTest(this, testName) {
                        // Removed questionnaire prompt to encourage continuous test flow
                    }
                }
            }, 400)
        }
    }
}
