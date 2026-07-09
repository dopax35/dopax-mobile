package com.pdcollect.app.ui

import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.os.CountDownTimer
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.logic.PostureCalibrationProfile
import com.pdcollect.app.logic.PostureEngine
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Minimal posture-calibration wizard. Walks the user through 5 head positions
 * (neutral, left, right, chin-down, look-up), capturing the live Madgwick-filter
 * gravity vector at each (via the shared PostureEngine, which BeanieService feeds
 * continuously while connected), then derives + saves a PostureCalibrationProfile
 * using the same axis-frame math as the reference iOS/Android calibration flows.
 *
 * Deliberately simple — visual instructions + countdown only, no voice synthesis,
 * beep tones, or waveform animation. No posture history/charts UI exists in this
 * app (by design), so this screen's only job is to produce a valid calibration.
 */
class PostureCalibrationActivity : AppCompatActivity() {

    private data class CalStep(
        val title: String,
        val instruction: String,
        val holdSec: Int,
        val capture: CaptureKind
    )

    private enum class CaptureKind { NEUTRAL, LEFT, RIGHT, CHIN, UP }

    private val steps = listOf(
        CalStep(
            "Step 1 of 5",
            "Sit or stand upright. Head balanced, chin level, shoulders relaxed.",
            8, CaptureKind.NEUTRAL
        ),
        CalStep(
            "Step 2 of 5",
            "Return to upright, then turn your head to look as far LEFT as comfortable.",
            6, CaptureKind.LEFT
        ),
        CalStep(
            "Step 3 of 5",
            "Return to upright, then turn your head to look as far RIGHT as comfortable.",
            6, CaptureKind.RIGHT
        ),
        CalStep(
            "Step 4 of 5",
            "Return to upright, then slowly lower your chin all the way down to your chest.",
            6, CaptureKind.CHIN
        ),
        CalStep(
            "Step 5 of 5",
            "Return to upright, then tilt your head back and look up at the ceiling.",
            6, CaptureKind.UP
        )
    )

    private lateinit var postureEngine: PostureEngine

    private lateinit var tvTitle: TextView
    private lateinit var tvInstruction: TextView
    private lateinit var tvCountdown: TextView
    private lateinit var progressBar: ProgressBar
    private lateinit var btnAction: MaterialButton
    private lateinit var btnCancel: MaterialButton

    private var stepIndex = -1
    private var timer: CountDownTimer? = null

    // Captured values
    private var neutralGrav: Triple<Double, Double, Double>? = null
    private var neutralPitch: Double? = null
    private var leftGrav: Triple<Double, Double, Double>? = null
    private var leftGz: Double? = null
    private var rightGrav: Triple<Double, Double, Double>? = null
    private var rightGz: Double? = null
    private var chinGrav: Triple<Double, Double, Double>? = null
    private var chinPitch: Double? = null
    private var upGrav: Triple<Double, Double, Double>? = null
    private var upPitch: Double? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (UserProfile(this).beanieDeviceAddress.isBlank()) {
            Toast.makeText(this, "Pair a Beanie device before calibrating posture", Toast.LENGTH_LONG).show()
            finish()
            return
        }

        postureEngine = PostureEngine.getInstance(applicationContext)
        buildUi()
        showIntro()
    }

    override fun onDestroy() {
        timer?.cancel()
        super.onDestroy()
    }

    // ── Programmatic UI (no XML layout — keeps this screen self-contained) ────

    private fun buildUi() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(32), dp(48), dp(32), dp(32))
            setBackgroundColor(Color.WHITE)
        }

        progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = steps.size
            isIndeterminate = false
        }
        root.addView(
            progressBar,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(6))
        )

        tvTitle = TextView(this).apply {
            textSize = 14f
            setTextColor(Color.parseColor("#757575"))
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        root.addView(
            tvTitle,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(28) }
        )

        tvInstruction = TextView(this).apply {
            textSize = 20f
            setTextColor(Color.parseColor("#212121"))
            gravity = Gravity.CENTER
        }
        root.addView(
            tvInstruction,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(24) }
        )

        tvCountdown = TextView(this).apply {
            textSize = 52f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.parseColor("#43A5BB"))
            gravity = Gravity.CENTER
        }
        root.addView(
            tvCountdown,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(20) }
        )

        // Flexible spacer — pushes the action buttons to the bottom of the screen.
        val spacer = View(this)
        root.addView(spacer, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))

        btnAction = MaterialButton(this).apply {
            text = "Begin Calibration"
            setOnClickListener { onActionTapped() }
        }
        root.addView(
            btnAction,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        )

        btnCancel = MaterialButton(
            this, null, com.google.android.material.R.attr.materialButtonOutlinedStyle
        ).apply {
            text = "Cancel"
            setOnClickListener { finish() }
        }
        root.addView(
            btnCancel,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(8) }
        )

        setContentView(root)
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    // ── Flow ────────────────────────────────────────────────────────────────

    private fun showIntro() {
        stepIndex = -1
        tvTitle.text = "Posture Calibration"
        tvInstruction.text = "This takes about a minute. You'll be asked to hold 5 head " +
            "positions briefly. Make sure the Beanie is on and connected before starting."
        tvCountdown.text = ""
        progressBar.progress = 0
        btnAction.text = "Begin Calibration"
        btnAction.isEnabled = true
        btnAction.setOnClickListener { onActionTapped() }
    }

    private fun onActionTapped() {
        if (postureEngine.currentAbsolutePitch() == null) {
            Toast.makeText(
                this,
                "Beanie isn't sending motion data yet. Make sure it's connected and try again.",
                Toast.LENGTH_LONG
            ).show()
            return
        }
        beginStep(0)
    }

    private fun beginStep(index: Int) {
        stepIndex = index
        val step = steps[index]
        progressBar.progress = index
        tvTitle.text = step.title
        tvInstruction.text = step.instruction
        btnAction.isEnabled = false
        tvCountdown.text = "Get ready…"

        // Brief pause so the user can read the instruction and get into position
        // before the hold-and-capture countdown starts.
        timer?.cancel()
        timer = object : CountDownTimer(3_000, 1_000) {
            override fun onTick(millisUntilFinished: Long) {
                tvCountdown.text = "${(millisUntilFinished / 1000) + 1}"
            }
            override fun onFinish() {
                startHoldCountdown(step)
            }
        }.start()
    }

    private fun startHoldCountdown(step: CalStep) {
        val totalMs = step.holdSec * 1000L
        timer?.cancel()
        timer = object : CountDownTimer(totalMs, 1_000) {
            override fun onTick(millisUntilFinished: Long) {
                tvCountdown.text = "Hold… ${(millisUntilFinished / 1000) + 1}"
            }
            override fun onFinish() {
                captureStep(step)
            }
        }.start()
    }

    private fun captureStep(step: CalStep) {
        val grav = postureEngine.currentGravityVector()
        val pitch = postureEngine.currentAbsolutePitch()

        when (step.capture) {
            CaptureKind.NEUTRAL -> { neutralGrav = grav; neutralPitch = pitch }
            CaptureKind.LEFT -> { leftGrav = grav; leftGz = postureEngine.meanGzOverWindow(step.holdSec) }
            CaptureKind.RIGHT -> { rightGrav = grav; rightGz = postureEngine.meanGzOverWindow(step.holdSec) }
            CaptureKind.CHIN -> { chinGrav = grav; chinPitch = pitch }
            CaptureKind.UP -> { upGrav = grav; upPitch = pitch }
        }

        tvCountdown.text = "Captured ✓"
        val next = stepIndex + 1
        if (next >= steps.size) {
            finalizeCalibration()
        } else {
            btnAction.text = "Next Position"
            btnAction.isEnabled = true
            btnAction.setOnClickListener { beginStep(next) }
        }
    }

    // ── Finalize: derive axis frame + validate + save ──────────────────────
    // Same math as the reference iOS/Android calibration flows this app's
    // PostureEngine/PostureCalibrationProfile were already ported from.

    private fun finalizeCalibration() {
        val neutral = neutralGrav
        val chin = chinGrav
        val nPitch = neutralPitch
        if (neutral == null || chin == null || nPitch == null) {
            showFailure("Calibration incomplete. Please try again.")
            return
        }

        val gravDistance = gravDist(neutral, chin)
        // 0.30 ≈ 18° of actual head movement (2·sin(9°) ≈ 0.313) — same
        // threshold used by the reference iOS/Android calibration flows.
        if (gravDistance < 0.30) {
            val angleDeg = 2.0 * asin(min(gravDistance / 2.0, 1.0)) * 180.0 / Math.PI
            showFailure(
                "Head movement too small (%.0f° detected, need at least 18°). ".format(angleDeg) +
                    "Make sure the beanie is on firmly and bring your chin all the way to " +
                    "your chest next time."
            )
            return
        }

        val profile = PostureCalibrationProfile()
        profile.neutralPitchDeg = nPitch
        profile.pitchRangeDeg = abs((chinPitch ?: nPitch) - nPitch)
        profile.forwardPitchSign = if ((chinPitch ?: nPitch) > nPitch) 1.0 else -1.0
        profile.leftTurnGzSign = leftGz?.takeIf { abs(it) > 3 }?.let { if (it > 0) 1.0 else -1.0 } ?: 1.0
        upPitch?.let { profile.upPitchRangeDeg = abs(it - nPitch) }

        profile.neutralGravX = neutral.first
        profile.neutralGravY = neutral.second
        profile.neutralGravZ = neutral.third

        makeAxis(neutral, chin)?.let { axis ->
            val ax = axis[0]
            val ay = axis[1]
            val az = axis[2]
            val range = axis[3]
            profile.fwdAxisX = ax; profile.fwdAxisY = ay; profile.fwdAxisZ = az; profile.fwdRange = range
            val dot = neutral.first * chin.first + neutral.second * chin.second + neutral.third * chin.third
            profile.gravTiltRangeDeg = acos(dot.coerceIn(-1.0, 1.0)) * 180.0 / Math.PI
        }

        upGrav?.let { up ->
            makeAxis(neutral, up)?.let { axis ->
                val ax = axis[0]
                val ay = axis[1]
                val az = axis[2]
                val range = axis[3]
                profile.backAxisX = ax; profile.backAxisY = ay; profile.backAxisZ = az; profile.backRange = range
            }
        }

        val left = leftGrav
        val right = rightGrav
        if (left != null && right != null) {
            val dx = left.first - right.first
            val dy = left.second - right.second
            val dz = left.third - right.third
            val mag = sqrt(dx * dx + dy * dy + dz * dz)
            if (mag > 0.01) {
                profile.latAxisX = dx / mag; profile.latAxisY = dy / mag; profile.latAxisZ = dz / mag
                profile.latHalfRange = mag / 2.0
            }
        }

        profile.calibratedAt = System.currentTimeMillis()
        postureEngine.applyCalibration(profile)

        tvTitle.text = "Calibration Complete"
        tvInstruction.text = "Your posture thresholds have been saved."
        tvCountdown.text = "✓"
        progressBar.progress = steps.size
        btnAction.text = "Done"
        btnAction.isEnabled = true
        btnAction.setOnClickListener { finish() }
        Toast.makeText(this, "Posture calibration saved", Toast.LENGTH_SHORT).show()
    }

    private fun showFailure(message: String) {
        tvTitle.text = "Calibration Failed"
        tvInstruction.text = message
        tvCountdown.text = ""
        btnAction.text = "Try Again"
        btnAction.isEnabled = true
        btnAction.setOnClickListener {
            resetCaptures()
            showIntro()
        }
    }

    private fun resetCaptures() {
        neutralGrav = null; neutralPitch = null
        leftGrav = null; leftGz = null
        rightGrav = null; rightGz = null
        chinGrav = null; chinPitch = null
        upGrav = null; upPitch = null
    }

    private fun gravDist(a: Triple<Double, Double, Double>, b: Triple<Double, Double, Double>): Double {
        val dx = b.first - a.first; val dy = b.second - a.second; val dz = b.third - a.third
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    /** Returns (ux, uy, uz, magnitude) or null if the movement was too small to be meaningful. */
    private fun makeAxis(
        from: Triple<Double, Double, Double>,
        to: Triple<Double, Double, Double>
    ): List<Double>? {
        val dx = to.first - from.first; val dy = to.second - from.second; val dz = to.third - from.third
        val mag = sqrt(dx * dx + dy * dy + dz * dz)
        if (mag < 0.01) return null
        return listOf(dx / mag, dy / mag, dz / mag, mag)
    }
}
