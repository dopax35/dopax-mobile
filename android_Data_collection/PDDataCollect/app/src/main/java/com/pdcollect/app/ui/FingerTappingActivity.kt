package com.pdcollect.app.ui

import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.os.CountDownTimer
import android.view.HapticFeedbackConstants
import android.view.View
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.util.Constants
import com.pdcollect.app.util.MotorTestSession

class FingerTappingActivity : AppCompatActivity() {

    private lateinit var dataManager: DataManager
    private lateinit var profile: UserProfile
    private lateinit var ivMole: android.widget.ImageView
    private lateinit var btnStartTapping: Button
    private lateinit var btnStartTappingStatus: Button
    private var isTestRunning = false
    private var isCountdownRunning = false
    private var tapCount = 0
    private var currentSide = Constants.PARTICIPANT_HAND_RIGHT
    private var moleIsOnLeft = false
    private var testTimer: CountDownTimer? = null
    private var isBatteryMode = false
    private var session: MotorTestSession? = null
    private var endRowWritten = false
    private val finishHandler = android.os.Handler(android.os.Looper.getMainLooper())

    // Finger-tapping header has 1 sensor column between event and side: button_id.
    private val sensorColCount = 1

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_finger_tapping)

        profile = UserProfile(this)
        dataManager = DataManager(this, profile)

        ivMole = findViewById(R.id.ivMole)
        btnStartTapping = findViewById(R.id.btnStartTapping)
        btnStartTappingStatus = findViewById(R.id.btnStartTappingStatus)
        ivMole.visibility = View.INVISIBLE // Hidden until test starts

        isBatteryMode = intent.getBooleanExtra("IS_BATTERY_MODE", false)
        val forceHand = intent.getStringExtra("EXTRA_HAND")
        if (isBatteryMode || forceHand != null) {
            currentSide = forceHand ?: Constants.PARTICIPANT_HAND_RIGHT
            findViewById<android.widget.RadioGroup>(R.id.rgSide).visibility = View.GONE
            findViewById<android.widget.TextView>(R.id.tvTitle).text = "Finger Tapping ($currentSide)"
        }

        btnStartTapping.setOnClickListener {
            startFingerTappingTest()
        }

        ivMole.setOnClickListener {
            whackMole()
        }
    }

    private fun startFingerTappingTest() {
        if (isCountdownRunning || isTestRunning) return
        // Lock side BEFORE we start the session so START + every SAMPLE row
        // carry the same hand label. Side is locked when the activity was
        // started in battery mode or relaunched with EXTRA_HAND for the
        // second hand; otherwise read it from the radio group.
        val sideLocked = isBatteryMode || intent.getStringExtra("EXTRA_HAND") != null
        if (!sideLocked) {
            currentSide = if (findViewById<RadioButton>(R.id.rbLeft).isChecked) {
                Constants.PARTICIPANT_HAND_LEFT
            } else {
                Constants.PARTICIPANT_HAND_RIGHT
            }
        }
        isCountdownRunning = true

        findViewById<View>(R.id.layoutInfo).visibility = View.GONE
        findViewById<View>(R.id.layoutTest).visibility = View.VISIBLE
        ivMole.visibility = View.INVISIBLE
        btnStartTappingStatus.visibility = View.VISIBLE
        btnStartTapping.setTestButtonState(enabled = false, label = "Starting...")
        btnStartTappingStatus.setTestButtonState(enabled = false, label = "Starting...")

        tapCount = 0
        findViewById<TextView>(R.id.tvTapCount).text = "Whacks: 0"

        // 3s countdown before start
        object : CountDownTimer(3000, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                findViewById<TextView>(R.id.tvTimer).text = (millisUntilFinished / 1000 + 1).toString()
            }

            override fun onFinish() {
                startActualTest()
            }
        }.start()
    }

    private fun startActualTest() {
        isCountdownRunning = false
        isTestRunning = true
        // Mark "test presented" the moment the mole becomes visible — that's
        // when the user can first react. The first SAMPLE row's elapsed_ms
        // is then the reaction time to first tap.
        val s = MotorTestSession(profile, currentSide)
        session = s
        dataManager.writeFingerTappingData(s.startRow(sensorColCount))
        btnStartTappingStatus.setTestButtonState(enabled = false, label = "Test Running")
        ivMole.visibility = View.VISIBLE
        moleIsOnLeft = currentSide == Constants.PARTICIPANT_HAND_LEFT
        positionMole(moleIsOnLeft) // Start on the selected hand's preferred side

        testTimer = object : CountDownTimer(10000, 100) {
            override fun onTick(millisUntilFinished: Long) {
                findViewById<TextView>(R.id.tvTimer).text = "${millisUntilFinished / 1000}s"
            }

            override fun onFinish() {
                finishTest()
            }
        }.start()
    }

    private fun whackMole() {
        if (!isTestRunning) return
        val s = session ?: return

        ivMole.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
        tapCount++
        findViewById<TextView>(R.id.tvTapCount).text = "Whacks: $tapCount"

        // `button_id` records WHICH on-screen button was tapped (LEFT vs RIGHT
        // half of the screen). For a single-hand trial this alternates every
        // tap because the mole jumps; the analyst correlates this with `side`
        // (which hand was used) to detect cross-body coordination.
        val buttonId = if (moleIsOnLeft) "LEFT" else "RIGHT"
        dataManager.writeFingerTappingData(s.sampleRow(buttonId))

        // Jump to other side
        moleIsOnLeft = !moleIsOnLeft
        positionMole(moleIsOnLeft)
    }

    private fun positionMole(isLeft: Boolean) {
        val params = ivMole.layoutParams as android.widget.FrameLayout.LayoutParams
        if (isLeft) {
            params.gravity = android.view.Gravity.CENTER_VERTICAL or android.view.Gravity.START
            params.marginStart = 48
            params.marginEnd = 0
        } else {
            params.gravity = android.view.Gravity.CENTER_VERTICAL or android.view.Gravity.END
            params.marginStart = 0
            params.marginEnd = 48
        }
        ivMole.layoutParams = params
    }

    private fun finishTest() {
        isCountdownRunning = false
        isTestRunning = false
        ivMole.visibility = View.INVISIBLE
        writeEndRow()
        findViewById<TextView>(R.id.tvTimer).text = "Done!"
        Toast.makeText(this, "Test complete: $tapCount whacks", Toast.LENGTH_LONG).show()

        val forceHand = intent.getStringExtra("EXTRA_HAND")
        finishHandler.postDelayed({
            if (isFinishing || isDestroyed) return@postDelayed
            if (isBatteryMode) {
                // Battery mode: signal coordinator to advance
                setResult(android.app.Activity.RESULT_OK)
                finish()
            } else if (currentSide == Constants.PARTICIPANT_HAND_RIGHT && forceHand == null) {
                // Standalone mode, first hand done: auto-advance to Left hand
                promptForLeftHand()
            } else {
                // Left hand done (or only-left selected) — go home
                finish()
            }
        }, 1500)
    }

    private fun promptForLeftHand() {
        AlertDialog.Builder(this)
            .setTitle("Right hand complete")
            .setMessage("Now let's test your LEFT hand.\n\nTap OK when you're ready.")
            .setCancelable(false)
            .setPositiveButton("OK — start left hand") { _, _ ->
                val intent = Intent(this, FingerTappingActivity::class.java).apply {
                    putExtra("EXTRA_HAND", Constants.PARTICIPANT_HAND_LEFT)
                    // Carry no IS_BATTERY_MODE so it stays in standalone mode
                }
                startActivity(intent)
                finish()
            }
            .setNegativeButton("Skip") { _, _ -> finish() }
            .show()
    }

    private fun writeEndRow() {
        val s = session ?: return
        if (endRowWritten) return
        endRowWritten = true
        dataManager.writeFingerTappingData(s.endRow(sensorColCount))
    }

    override fun onDestroy() {
        testTimer?.cancel()
        // Cancel any pending post-test transition — without this, a Back-press during
        // the 1.5s window after finishTest() still fires the delayed callback against a
        // finishing/destroyed Activity, and AlertDialog.show() below throws BadTokenException.
        finishHandler.removeCallbacksAndMessages(null)
        // Backstop: if the activity dies mid-trial, still write END.
        writeEndRow()
        dataManager.closeAll()
        super.onDestroy()
    }
}
