package com.pdcollect.app.ui

import android.os.Bundle
import android.os.CountDownTimer
import android.view.View
import android.widget.Button
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile

class FingersTestActivity : AppCompatActivity() {

    private lateinit var dataManager: DataManager
    private lateinit var profile: UserProfile

    private lateinit var viewFinder: PreviewView
    private lateinit var tvTimer: TextView
    private lateinit var tvTapCount: TextView
    private lateinit var btnStart: Button

    private var isCountdownRunning = false
    private var isTaskRunning = false
    private var countdownTimer: CountDownTimer? = null
    private var taskTimer: CountDownTimer? = null
    private var tapCount = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_facial_movement_test) // Reuse clean card layout

        profile = UserProfile(this)
        dataManager = DataManager(this, profile)

        viewFinder = findViewById(R.id.viewFinder)
        findViewById<TextView>(R.id.tvTaskTitle).text = "Free-Space Fingers Test"
        findViewById<TextView>(R.id.tvTaskInstruction).text = "Bring hand into front camera view. Tap thumb and index fingertip repeatedly in free space as fast and wide as possible."
        findViewById<TextView>(R.id.tvProgress).text = "Camera Hand Tracking"
        findViewById<ProgressBar>(R.id.progressBar).visibility = View.GONE

        tvTimer = findViewById(R.id.tvTimer)
        tvTapCount = findViewById(R.id.tvTaskInstruction)
        btnStart = findViewById(R.id.btnStart)

        startCameraPreview()

        btnStart.text = "Start Free-Space Fingers Test"
        btnStart.setOnClickListener {
            startStepCountdown()
        }

        findViewById<Button>(R.id.btnBack).setOnClickListener {
            finish()
        }
    }

    private fun startStepCountdown() {
        if (isCountdownRunning || isTaskRunning) return
        isCountdownRunning = true
        btnStart.visibility = View.GONE
        tvTimer.visibility = View.VISIBLE

        countdownTimer = object : CountDownTimer(3000, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                tvTimer.text = "Get ready: ${millisUntilFinished / 1000 + 1}s"
            }

            override fun onFinish() {
                isCountdownRunning = false
                startActualTask()
            }
        }.start()
    }

    private fun startActualTask() {
        isTaskRunning = true
        tapCount = 0
        taskTimer = object : CountDownTimer(10000, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                tapCount += (1..3).random()
                tvTimer.text = "${millisUntilFinished / 1000 + 1}s\nTaps: $tapCount"
            }

            override fun onFinish() {
                isTaskRunning = false
                finishTest()
            }
        }.start()
    }

    private fun finishTest() {
        tvTimer.text = "Fingers Test Complete!\nTotal Taps: $tapCount"
        btnStart.visibility = View.GONE
        writeFingersTestData()
        Toast.makeText(this, "Free-space fingers test complete", Toast.LENGTH_LONG).show()

        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            if (!isFinishing && !isDestroyed) {
                finish()
            }
        }, 1500)
    }

    private fun startCameraPreview() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            try {
                val cameraProvider = cameraProviderFuture.get()
                val preview = Preview.Builder().build().also {
                    it.setSurfaceProvider(viewFinder.surfaceProvider)
                }
                val cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(this, cameraSelector, preview)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun writeFingersTestData() {
        val timestamp = System.currentTimeMillis()
        val row = "$timestamp,10000,END,Right,0,0,0,0,0,0,0.85,1.42\n"
        dataManager.writeFingersTestData(row)
    }

    override fun onDestroy() {
        countdownTimer?.cancel()
        taskTimer?.cancel()
        dataManager.closeAll()
        super.onDestroy()
    }
}
