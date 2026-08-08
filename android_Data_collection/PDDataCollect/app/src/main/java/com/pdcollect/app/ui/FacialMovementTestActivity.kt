package com.pdcollect.app.ui

import android.os.Bundle
import android.os.CountDownTimer
import android.view.View
import android.widget.Button
import android.widget.ImageView
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

class FacialMovementTestActivity : AppCompatActivity() {

    private lateinit var dataManager: DataManager
    private lateinit var profile: UserProfile

    private lateinit var viewFinder: PreviewView
    private lateinit var tvTaskTitle: TextView
    private lateinit var tvTaskInstruction: TextView
    private lateinit var tvTimer: TextView
    private lateinit var tvProgress: TextView
    private lateinit var progressBar: ProgressBar
    private lateinit var btnStart: Button
    private lateinit var ivIcon: ImageView

    private var currentStepIndex = 0
    private var isCountdownRunning = false
    private var isTaskRunning = false
    private var countdownTimer: CountDownTimer? = null
    private var taskTimer: CountDownTimer? = null

    private val tasks = listOf(
        TaskInfo("Neutral Rest", "Keep your face completely relaxed at rest.", android.R.drawable.ic_menu_camera),
        TaskInfo("Eyebrow Raise", "Raise eyebrows as high as comfortable.", android.R.drawable.ic_menu_camera),
        TaskInfo("Full Smile", "Smile broadly showing your teeth.", android.R.drawable.ic_menu_camera),
        TaskInfo("Mouth Pucker", "Pucker your lips firmly forward.", android.R.drawable.ic_menu_camera),
        TaskInfo("Rapid Blinking", "Blink rapidly and repeatedly for 5 seconds.", android.R.drawable.ic_menu_camera)
    )

    data class TaskInfo(val title: String, val instruction: String, val iconRes: Int)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_facial_movement_test)

        profile = UserProfile(this)
        dataManager = DataManager(this, profile)

        viewFinder = findViewById(R.id.viewFinder)
        tvTaskTitle = findViewById(R.id.tvTaskTitle)
        tvTaskInstruction = findViewById(R.id.tvTaskInstruction)
        tvTimer = findViewById(R.id.tvTimer)
        tvProgress = findViewById(R.id.tvProgress)
        progressBar = findViewById(R.id.progressBar)
        btnStart = findViewById(R.id.btnStart)
        ivIcon = findViewById(R.id.ivIcon)

        startCameraPreview()

        updateStepUi()

        btnStart.setOnClickListener {
            startStepCountdown()
        }

        findViewById<Button>(R.id.btnBack).setOnClickListener {
            finish()
        }
    }

    private fun updateStepUi() {
        val task = tasks[currentStepIndex]
        tvTaskTitle.text = task.title
        tvTaskInstruction.text = task.instruction
        tvProgress.text = "Step ${currentStepIndex + 1} of ${tasks.size}"
        progressBar.progress = (currentStepIndex + 1) * 100 / tasks.size
        tvTimer.visibility = View.GONE
        btnStart.visibility = View.VISIBLE
        btnStart.text = "Start ${task.title}"
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
        taskTimer = object : CountDownTimer(5000, 100) {
            override fun onTick(millisUntilFinished: Long) {
                tvTimer.text = "Recording... ${millisUntilFinished / 1000 + 1}s"
            }

            override fun onFinish() {
                isTaskRunning = false
                if (currentStepIndex + 1 < tasks.size) {
                    currentStepIndex++
                    updateStepUi()
                } else {
                    finishTest()
                }
            }
        }.start()
    }

    private fun finishTest() {
        tvTimer.text = "Facial Movement Test Complete!"
        btnStart.visibility = View.GONE
        Toast.makeText(this, "Facial Movement Test complete", Toast.LENGTH_LONG).show()

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

    override fun onDestroy() {
        countdownTimer?.cancel()
        taskTimer?.cancel()
        dataManager.closeAll()
        super.onDestroy()
    }
}
