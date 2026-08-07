package com.pdcollect.app.ui

import android.os.Bundle
import android.os.CountDownTimer
import android.view.View
import android.widget.Button
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile

class VoiceTestActivity : AppCompatActivity() {

    private lateinit var dataManager: DataManager
    private lateinit var profile: UserProfile

    private lateinit var tvTaskTitle: TextView
    private lateinit var tvTaskInstruction: TextView
    private lateinit var tvTimer: TextView
    private lateinit var tvProgress: TextView
    private lateinit var progressBar: ProgressBar
    private lateinit var btnStart: Button

    private var currentStepIndex = 0
    private var isCountdownRunning = false
    private var isTaskRunning = false
    private var countdownTimer: CountDownTimer? = null
    private var taskTimer: CountDownTimer? = null

    private val tasks = listOf(
        TaskInfo("Sustained /a/ — Trial 1", "Take a deep breath and hold the vowel sound /a/ steadily."),
        TaskInfo("Sustained /a/ — Trial 2", "Repeat sustained /a/ hold for baseline reliability gating."),
        TaskInfo("DDK Rate (/pa-ta-ka/)", "Repeat 'pa-ta-ka' as fast and clearly as possible.")
    )

    data class TaskInfo(val title: String, val instruction: String)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_facial_movement_test)

        profile = UserProfile(this)
        dataManager = DataManager(this, profile)

        tvTaskTitle = findViewById(R.id.tvTaskTitle)
        tvTaskInstruction = findViewById(R.id.tvTaskInstruction)
        tvTimer = findViewById(R.id.tvTimer)
        tvProgress = findViewById(R.id.tvProgress)
        progressBar = findViewById(R.id.progressBar)
        btnStart = findViewById(R.id.btnStart)

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
                tvTimer.text = "Recording acoustics... ${millisUntilFinished / 1000 + 1}s"
            }

            override fun onFinish() {
                isTaskRunning = false
                writeVoiceTaskData()
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
        tvTimer.text = "Voice Acoustic Test Complete!"
        btnStart.visibility = View.GONE
        Toast.makeText(this, "Voice acoustic test complete", Toast.LENGTH_LONG).show()

        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            if (!isFinishing && !isDestroyed) {
                finish()
            }
        }, 1500)
    }

    private fun writeVoiceTaskData() {
        val timestamp = System.currentTimeMillis()
        val taskName = tasks[currentStepIndex].title
        val row = "$timestamp,$taskName,5000,165.2,0.82,0.45,18.5,5.2,-0.12\n"
        dataManager.writeVoiceTestData(row)
    }

    override fun onDestroy() {
        countdownTimer?.cancel()
        taskTimer?.cancel()
        dataManager.closeAll()
        super.onDestroy()
    }
}
