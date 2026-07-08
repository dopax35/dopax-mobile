package com.pdcollect.app.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.os.Bundle
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.service.FaceDistanceRecorder
import com.pdcollect.app.util.Constants
import com.pdcollect.app.util.PermissionUtils
import com.pdcollect.app.util.TimeUtils
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.sqrt

class TrailMakingTestActivity : AppCompatActivity() {

    private lateinit var dataManager: DataManager
    private lateinit var profile: UserProfile
    private lateinit var tmtView: TMTCanvasView
    private lateinit var tvInstructions: TextView
    private lateinit var btnStart: Button
    private lateinit var btnFinish: Button
    private var faceDistanceRecorder: FaceDistanceRecorder? = null

    private var currentTestType = "A" // "A" or "B"
    private var isTestRunning = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_trail_making_test)

        if (savedInstanceState != null) {
            currentTestType = savedInstanceState.getString("KEY_TEST_TYPE", "A")
        }
        
        profile = UserProfile(this)
        dataManager = DataManager(this, profile)

        tvInstructions = findViewById(R.id.tvTmtInstructions)
        btnStart = findViewById(R.id.btnStartTmt)
        btnFinish = findViewById(R.id.btnFinishTmt)
        val container = findViewById<FrameLayout>(R.id.tmtContainer)

        tmtView = TMTCanvasView(this)
        container.addView(tmtView)

        tvInstructions.text = "Trail Making Test - Part A\n\nConnect the numbers in order (1→2→3→...→10) as quickly as possible.\n\nTap 'Start' when ready."

        btnStart.setOnClickListener {
            if (isTestRunning) return@setOnClickListener
            startTmtDistanceCaptureIfNeeded()
            btnFinish.visibility = View.GONE
            if (currentTestType == "A") {
                tmtView.startTest(Companion.generatePartATargets())
                tvInstructions.text = "Part A: Connect 1→2→3→...→10"
            } else {
                tmtView.startTest(Companion.generatePartBTargets())
                tvInstructions.text = "Part B: Connect 1→A→2→B→...→5"
            }
            isTestRunning = true
            btnStart.setTestButtonState(enabled = false, label = "Test Running")
        }

        tmtView.onTestComplete = { absoluteStart, totalTime, wrongTargetErrors, liftOffErrors, pathData ->
            isTestRunning = false
            saveResult(absoluteStart, currentTestType, totalTime, wrongTargetErrors, liftOffErrors, pathData)
            val errorSummary = "Errors: ${wrongTargetErrors + liftOffErrors} " +
                "($wrongTargetErrors wrong-target, $liftOffErrors lift-off)"
            if (currentTestType == "A") {
                currentTestType = "B"
                tvInstructions.text = "Part A Complete! Time: ${totalTime}ms, $errorSummary\n\nNow Part B: Connect numbers and letters alternating (1→A→2→B→...→5).\n\nTap 'Start Part B'."
                btnStart.setTestButtonState(enabled = true, label = "Start Part B")
            } else {
                tvInstructions.text = "Part B Complete! Time: ${totalTime}ms, $errorSummary\n\nThank you! Both tests are done."
                btnStart.setTestButtonState(enabled = true, label = "Restart Part A")
                btnFinish.visibility = View.VISIBLE
                currentTestType = "A"
                stopTmtDistanceCapture()
                Toast.makeText(this, "TMT Complete!", Toast.LENGTH_LONG).show()
                
                if (intent.getBooleanExtra("IS_BATTERY_MODE", false)) {
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        setResult(android.app.Activity.RESULT_OK)
                        finish()
                    }, 1500)
                }
            }
        }

        btnFinish.setOnClickListener {
            stopTmtDistanceCapture()
            if (intent.getBooleanExtra("IS_BATTERY_MODE", false)) {
                setResult(android.app.Activity.RESULT_OK)
            }
            finish()
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString("KEY_TEST_TYPE", currentTestType)
    }

    private fun startTmtDistanceCaptureIfNeeded() {
        val needsLocalTmtRecorder = when (profile.faceDistanceMode) {
            Constants.FACE_DISTANCE_MODE_TMT_ONLY -> true
            Constants.FACE_DISTANCE_MODE_APP_FOREGROUND -> !profile.passiveCollectionActive
            Constants.FACE_DISTANCE_MODE_ALWAYS -> !profile.passiveCollectionActive
            else -> false
        }
        if (!needsLocalTmtRecorder) return
        if (faceDistanceRecorder != null) return
        if (!PermissionUtils.hasCameraPermission(this)) return

        faceDistanceRecorder = FaceDistanceRecorder(
            context = this,
            lifecycleOwner = this,
            captureContext = Constants.FACE_DISTANCE_CONTEXT_TMT,
            onSample = { sample -> dataManager.writeFaceDistanceData(sample.toCsvRow()) },
            onBlink  = { blink  -> dataManager.writeBlinkData(blink.toCsvRow()) },
            onError  = { android.util.Log.e("TrailMakingTest", "TMT face capture failed", it) }
        ).also { it.start() }
    }

    private fun stopTmtDistanceCapture() {
        faceDistanceRecorder?.stop()
        faceDistanceRecorder = null
    }

    private fun saveResult(
        startTimeMs: Long, testType: String, totalTime: Long,
        wrongTargetErrors: Int, liftOffErrors: Int, pathData: String
    ) {
        val timestamp = TimeUtils.currentTimeMs()
        val segmentTimings = tmtView.getSegmentTimings()
        val fingerPath = tmtView.getFingerPath()
        val row = "$startTimeMs,$timestamp,$testType,$totalTime,$wrongTargetErrors,$liftOffErrors," +
                "\"${segmentTimings.replace("\"", "\"\"")}\",\"${fingerPath.replace("\"", "\"\"")}\",\"${pathData.replace("\"", "\"\"")}\""
        dataManager.writeTmtResult(row)
    }

    override fun onDestroy() {
        stopTmtDistanceCapture()
        dataManager.closeAll()
        super.onDestroy()
    }

    data class TMTTarget(val label: String, val index: Int, var x: Float = 0f, var y: Float = 0f)

    companion object {
        fun generatePartATargets(): List<TMTTarget> {
            return (1..10).map { i ->
                TMTTarget(label = i.toString(), index = i - 1)
            }
        }

        fun generatePartBTargets(): List<TMTTarget> {
            val targets = mutableListOf<TMTTarget>()
            val letters = "ABCDE"
            for (i in 1..5) {
                targets.add(TMTTarget(label = i.toString(), index = targets.size))
                if (i <= 4) {
                    targets.add(TMTTarget(label = letters[i - 1].toString(), index = targets.size))
                }
            }
            return targets
        }

        fun layoutTargets(
            targets: List<TMTTarget>,
            width: Int,
            height: Int,
            circleRadius: Float,
            random: java.util.Random = java.util.Random()
        ): List<TMTTarget> {
            val padding = circleRadius * 2.5f
            val bottomPadding = padding + 200f
            val positions = mutableListOf<Pair<Float, Float>>()

            for (target in targets) {
                var x: Float
                var y: Float
                var attempts = 0
                do {
                    x = padding + random.nextFloat() * (width - 2 * padding)
                    y = padding + random.nextFloat() * (height - padding - bottomPadding)
                    attempts++
                } while (positions.any { (px, py) ->
                        sqrt((x - px) * (x - px) + (y - py) * (y - py)) < circleRadius * 4
                    } && attempts < 200)
                target.x = x
                target.y = y
                positions.add(x to y)
            }
            return targets
        }
    }

    class TMTCanvasView @JvmOverloads constructor(
        context: Context, attrs: AttributeSet? = null
    ) : View(context, attrs) {

        private var targets = listOf<TMTTarget>()
        private var currentIndex = 0
        private var startTime = 0L
        private var absoluteStartTimeMs = 0L
        // Two clinically-distinct TMT error types, both tracked and logged
        // separately (matching iOS): touching the wrong numbered/lettered
        // target, and lifting the finger before the whole trail is complete.
        private var wrongTargetErrors = 0
        private var liftOffErrors = 0
        private var isActive = false
        private val connectedPath = Path()
        private val segmentTimes = mutableListOf<JSONObject>()
        private var lastSegmentTime = 0L
        private val fingerPathPoints = JSONArray()
        private var isTracingActive = false
        private var currentFingerX = 0f
        private var currentFingerY = 0f
        private var activeTracePath = Path()
        // Index of the wrong target the finger is currently resting on, or -1.
        // Used to edge-trigger error counting in checkWrongTargets() so one
        // errant touch isn't counted dozens of times across ACTION_MOVE events.
        private var activeWrongTargetIndex = -1

        var onTestComplete: ((absoluteStart: Long, totalTime: Long, wrongTargetErrors: Int, liftOffErrors: Int, pathData: String) -> Unit)? = null

        private val circlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.FILL
        }
        private val circleStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.DKGRAY
            style = Paint.Style.STROKE
            strokeWidth = 3f
        }
        private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textSize = 48f
            textAlign = Paint.Align.CENTER
        }
        // Brand-consistent: confirmed path segments use the primary Dopa-X blue;
        // the live in-progress trace uses the secondary purple, so the two are
        // always visually distinct without introducing an off-palette color.
        private val completedPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ContextCompat.getColor(context, R.color.blue)
            style = Paint.Style.FILL
        }
        private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ContextCompat.getColor(context, R.color.blue)
            style = Paint.Style.STROKE
            strokeWidth = 4f
        }
        private val touchLinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ContextCompat.getColor(context, R.color.purple)
            style = Paint.Style.STROKE
            strokeWidth = 6f
            strokeCap = Paint.Cap.ROUND
        }

        private val circleRadius = 50f

        fun startTest(newTargets: List<TMTTarget>) {
            targets = newTargets
            currentIndex = 0
            wrongTargetErrors = 0
            liftOffErrors = 0
            isActive = true
            startTime = System.currentTimeMillis()
            absoluteStartTimeMs = startTime
            connectedPath.reset()
            segmentTimes.clear()
            lastSegmentTime = 0L
            fingerPathPoints.apply { while (length() > 0) remove(0) }
            isTracingActive = false
            activeTracePath.reset()
            activeWrongTargetIndex = -1
            layoutTargets()
            invalidate()
        }

        private fun logTargets() {
            for (t in targets) {
                android.util.Log.d("TMT", "Target ${t.label} at (${t.x}, ${t.y})")
            }
            android.util.Log.d("TMT", "View size: ${width}x${height}")
        }

        private fun layoutTargets() {
            if (width == 0 || height == 0) {
                post { layoutTargets(); invalidate() }
                return
            }
            Companion.layoutTargets(targets, width, height, circleRadius)
            logTargets()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            canvas.drawColor(ContextCompat.getColor(context, R.color.surface_container_low))

            // Draw connection lines
            canvas.drawPath(connectedPath, linePaint)
            if (isTracingActive) {
                canvas.drawPath(activeTracePath, touchLinePaint)
            }

            // Draw targets
            for ((i, target) in targets.withIndex()) {
                val paint = when {
                    i < currentIndex -> completedPaint
                    else -> circlePaint
                }
                canvas.drawCircle(target.x, target.y, circleRadius, paint)
                canvas.drawCircle(target.x, target.y, circleRadius, circleStrokePaint)
                canvas.drawText(
                    target.label,
                    target.x,
                    target.y + textPaint.textSize / 3,
                    textPaint
                )
            }
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            if (!isActive) return true

            val x = event.x
            val y = event.y

            val timestamp = System.currentTimeMillis()
            val elapsed = timestamp - startTime
            
            fingerPathPoints.put(JSONObject().apply {
                put("t", elapsed)
                put("t_abs", timestamp)
                put("x", x.toInt())
                put("y", y.toInt())
                put("a", event.action)
            })

            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    if (currentIndex == 0) {
                        // Starting the whole test: must touch dot 1
                        if (isTouchOnTarget(x, y, targets[0])) {
                            currentIndex = 1
                            isTracingActive = true
                            lastSegmentTime = elapsed
                            invalidate()
                        }
                    } else if (currentIndex < targets.size) {
                        // Middle of test: must touch the LAST completed dot to start tracing
                        if (isTouchOnTarget(x, y, targets[currentIndex - 1])) {
                            isTracingActive = true
                            invalidate()
                        }
                    }
                }
                MotionEvent.ACTION_MOVE -> {
                    if (isTracingActive) {
                        currentFingerX = x
                        currentFingerY = y
                        val prev = targets[currentIndex - 1]
                        activeTracePath.reset()
                        activeTracePath.moveTo(prev.x, prev.y)
                        activeTracePath.lineTo(x, y)
                        
                        // Check if we hit the NEXT target
                        if (currentIndex < targets.size && isTouchOnTarget(x, y, targets[currentIndex])) {
                            completeSegment(elapsed)
                        } else {
                            checkWrongTargets(x, y)
                        }
                        invalidate()
                    }
                }
                MotionEvent.ACTION_UP -> {
                    // Lifting the finger while actively tracing, before the
                    // whole trail is complete, is the second clinically-scored
                    // TMT error type (mirrors iOS, which has always tracked
                    // this one). Resuming just requires touching back down on
                    // the last completed target — see ACTION_DOWN above.
                    if (isTracingActive && currentIndex in 1 until targets.size) {
                        liftOffErrors++
                    }
                    isTracingActive = false
                    activeTracePath.reset()
                    activeWrongTargetIndex = -1
                    invalidate()
                }
            }
            return true
        }

        private fun isTouchOnTarget(tx: Float, ty: Float, target: TMTTarget): Boolean {
            val d = sqrt((tx - target.x) * (tx - target.x) + (ty - target.y) * (ty - target.y))
            return d <= circleRadius * 1.8f
        }

        private fun completeSegment(elapsed: Long) {
            val target = targets[currentIndex]
            val segmentDuration = elapsed - lastSegmentTime
            segmentTimes.add(JSONObject().apply {
                put("from", targets[currentIndex - 1].label)
                put("to", target.label)
                put("duration_ms", segmentDuration)
                put("elapsed_ms", elapsed)
            })
            lastSegmentTime = elapsed

            val prev = targets[currentIndex - 1]
            connectedPath.moveTo(prev.x, prev.y)
            connectedPath.lineTo(target.x, target.y)
            
            currentIndex++
            
            if (currentIndex >= targets.size) {
                isActive = false
                isTracingActive = false
                onTestComplete?.invoke(absoluteStartTimeMs, elapsed, wrongTargetErrors, liftOffErrors, fingerPathPoints.toString())
            }
        }

        /**
         * Flags a mistake when the finger is over any target other than the
         * one it started tracing from and the one it's heading to next.
         * Previously this method was never called from onTouchEvent, so
         * wrong-target errors — one of the two clinically-scored TMT error
         * types, alongside lift-offs and completion time — was always
         * recorded as zero.
         *
         * ACTION_MOVE fires far more often than once per real mistake, so
         * this edge-triggers on activeWrongTargetIndex: an error is only
         * counted the moment the finger *enters* a wrong target, not on
         * every subsequent move event while it's still resting there.
         */
        private fun checkWrongTargets(x: Float, y: Float) {
            val hitIndex = targets.indexOfFirst { isTouchOnTarget(x, y, it) }
            val isMistake = hitIndex != -1 &&
                hitIndex != currentIndex &&
                !(hitIndex == currentIndex - 1 && isTracingActive)

            if (isMistake) {
                if (activeWrongTargetIndex != hitIndex) {
                    wrongTargetErrors++
                    activeWrongTargetIndex = hitIndex
                }
            } else {
                activeWrongTargetIndex = -1
            }
        }

        fun getSegmentTimings(): String {
            val arr = JSONArray()
            for (obj in segmentTimes) arr.put(obj)
            return arr.toString()
        }

        fun getFingerPath(): String = fingerPathPoints.toString()
    }
}
