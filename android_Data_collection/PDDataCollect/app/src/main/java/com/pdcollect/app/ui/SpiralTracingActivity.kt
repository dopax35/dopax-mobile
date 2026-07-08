package com.pdcollect.app.ui

import android.os.Bundle
import android.widget.Button
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.ui.view.SpiralCanvasView
import com.pdcollect.app.util.Constants
import com.pdcollect.app.util.MotorTestSession

/**
 * Spiral tracing motor test.
 *
 * History note (April 2026): the original implementation derived "test start
 * time" from the first ACTION_DOWN on the canvas. That meant analysts couldn't
 * tell the difference between "subject saw the spiral and immediately traced"
 * (a fast-PD-progression signal is uncommon here) and "subject stared at the
 * spiral for 30 s before tracing" (a real PD-relevant latency signal). This
 * version emits an explicit START row when the canvas template is first drawn
 * for the user, plus an END row when they tap Finish, with monotonic
 * elapsed-ms timing on every row so the latency to first touch is computable.
 */
class SpiralTracingActivity : AppCompatActivity() {

    private lateinit var dataManager: DataManager
    private lateinit var profile: UserProfile

    private var currentSide = Constants.PARTICIPANT_HAND_RIGHT
    private var session: MotorTestSession? = null
    private var endRowWritten = false

    // Spiral header has 3 sensor columns between `event` and `side`: x, y, action.
    private val sensorColCount = 3

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_spiral_tracing)

        profile = UserProfile(this)
        dataManager = DataManager(this, profile)

        val canvas = findViewById<SpiralCanvasView>(R.id.spiralCanvas)

        val isBatteryMode = intent.getBooleanExtra("IS_BATTERY_MODE", false)
        val forceHand = intent.getStringExtra("EXTRA_HAND")
        val sideLocked = isBatteryMode || forceHand != null

        if (sideLocked) {
            currentSide = forceHand ?: Constants.PARTICIPANT_HAND_RIGHT
            findViewById<android.widget.RadioGroup>(R.id.rgSide).visibility = android.view.View.GONE
            findViewById<android.widget.TextView>(R.id.tvTitle)?.text = "Spiral Tracing ($currentSide)"
        }

        // Capture the canonical "test presented" timestamp the moment the
        // spiral template has actually been drawn on screen. This is the fix
        // for the missing-start-time bug — previously we had no row for this
        // event at all, so reaction latency was unrecoverable.
        canvas.onCanvasReady = {
            // Lock side from the radio button before writing START so the
            // START row's `side` matches what the trial will record.
            if (!sideLocked) {
                currentSide = readSideFromRadio()
            }
            if (session == null) {
                val s = MotorTestSession(profile, currentSide)
                session = s
                dataManager.writeSpiralData(s.startRow(sensorColCount))
            }
        }

        canvas.onTouchData = { x, y, action ->
            // Lazy fallback: if for some reason onCanvasReady didn't fire
            // (e.g. window race), still emit a START row before the first
            // sample so the schema is always valid.
            if (session == null) {
                if (!sideLocked) currentSide = readSideFromRadio()
                val s = MotorTestSession(profile, currentSide)
                session = s
                dataManager.writeSpiralData(s.startRow(sensorColCount))
            }
            val s = session!!
            // Sensor cols for spiral are x,y,action (3 columns).
            dataManager.writeSpiralData(s.sampleRow("$x,$y,$action"))
        }

        findViewById<Button>(R.id.btnFinishSpiral).setOnClickListener {
            it.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
            writeEndRow()
            Toast.makeText(this, "Spiral tracing ($currentSide) saved", Toast.LENGTH_SHORT).show()

            if (isBatteryMode) {
                setResult(android.app.Activity.RESULT_OK)
                finish()
            } else if (currentSide == Constants.PARTICIPANT_HAND_RIGHT && forceHand == null) {
                promptForLeftHand()
            } else {
                finish()
            }
        }
    }

    /** Read the user's radio-button choice; defaults to Right if neither set. */
    private fun readSideFromRadio(): String =
        if (findViewById<android.widget.RadioButton>(R.id.rbLeft).isChecked) {
            Constants.PARTICIPANT_HAND_LEFT
        } else {
            Constants.PARTICIPANT_HAND_RIGHT
        }

    /**
     * Write the END row exactly once. Called from the Finish button and from
     * onDestroy so a backgrounded / killed activity still leaves a valid
     * trial in the CSV.
     */
    private fun writeEndRow() {
        val s = session ?: return
        if (endRowWritten) return
        endRowWritten = true
        dataManager.writeSpiralData(s.endRow(sensorColCount))
    }

    override fun onDestroy() {
        writeEndRow()
        // Without this, DataManager's background HandlerThread and open CSV
        // writer are never closed — every spiral-tracing attempt (this screen
        // is re-launched per hand) leaks a thread, and any buffered touch
        // samples that hadn't hit the periodic flush yet are silently lost.
        // All the other motor-test activities already close their DataManager
        // here; this one was missing it.
        dataManager.closeAll()
        super.onDestroy()
    }

    private fun promptForLeftHand() {
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Right hand complete")
            .setMessage("Now let's trace with your LEFT hand.\n\nTap OK when you're ready.")
            .setCancelable(false)
            .setPositiveButton("OK — start left hand") { _, _ ->
                val intent = android.content.Intent(this, SpiralTracingActivity::class.java).apply {
                    putExtra("EXTRA_HAND", Constants.PARTICIPANT_HAND_LEFT)
                }
                startActivity(intent)
                finish()
            }
            .setNegativeButton("Skip") { _, _ -> finish() }
            .show()
    }
}
