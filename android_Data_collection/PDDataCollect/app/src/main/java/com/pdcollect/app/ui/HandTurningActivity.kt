package com.pdcollect.app.ui

import android.content.pm.ActivityInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Bundle
import android.os.CountDownTimer
import android.speech.tts.TextToSpeech
import android.view.View
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.util.Constants
import com.pdcollect.app.util.MotorTestSession
import java.util.Locale

class HandTurningActivity : AppCompatActivity(), SensorEventListener, TextToSpeech.OnInitListener {

    private lateinit var dataManager: DataManager
    private lateinit var profile: UserProfile
    private lateinit var sensorManager: SensorManager
    private lateinit var btnStartTurning: Button
    private var isTestRunning = false
    private var isCountdownRunning = false
    private var currentSide = Constants.PARTICIPANT_HAND_RIGHT
    private var countdownTimer: CountDownTimer? = null
    private var testTimer: CountDownTimer? = null
    private var session: MotorTestSession? = null
    private var endRowWritten = false
    private var textToSpeech: TextToSpeech? = null
    private var isTextToSpeechReady = false

    // Hand-turning header has 6 sensor columns: gx,gy,gz,ax,ay,az.
    private val sensorColCount = 6

    private var accelValues = FloatArray(3)
    private var gyroValues = FloatArray(3)
    private val toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, 100)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Freeze the current orientation so pronation/supination motion does
        // not trigger activity recreation on aggressive auto-rotate devices.
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LOCKED
        setContentView(R.layout.activity_hand_turning)

        profile = UserProfile(this)
        dataManager = DataManager(this, profile)
        sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        btnStartTurning = findViewById(R.id.btnStartTurning)
        textToSpeech = TextToSpeech(this, this)

        val isBatteryMode = intent.getBooleanExtra("IS_BATTERY_MODE", false)
        val forceHand = intent.getStringExtra("EXTRA_HAND")
        if (isBatteryMode || forceHand != null) {
            currentSide = forceHand ?: Constants.PARTICIPANT_HAND_RIGHT
            findViewById<RadioGroup>(R.id.rgSide).visibility = View.GONE
            findViewById<TextView>(R.id.tvTitle)?.text = "Hand Turning ($currentSide)"
        }

        btnStartTurning.setOnClickListener {
            it.performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY)
            startTest()
        }
    }

    private fun startTest() {
        if (isCountdownRunning || isTestRunning) return
        // If side wasn't pre-locked by intent extra, read it from the radio
        // group. Lock it BEFORE starting the session so START + every SAMPLE
        // row carry the same `side` value.
        val sideLocked = intent.getBooleanExtra("IS_BATTERY_MODE", false) ||
            intent.getStringExtra("EXTRA_HAND") != null
        if (!sideLocked) {
            currentSide = if (findViewById<RadioButton>(R.id.rbLeft).isChecked) {
                Constants.PARTICIPANT_HAND_LEFT
            } else {
                Constants.PARTICIPANT_HAND_RIGHT
            }
        }
        isCountdownRunning = true
        btnStartTurning.setTestButtonState(enabled = false, label = "Starting...")
        findViewById<RadioGroup>(R.id.rgSide).isEnabled = false
        speakCue("Get ready")

        // 3s countdown
        countdownTimer = object : CountDownTimer(3000, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                findViewById<TextView>(R.id.tvTimer).text = (millisUntilFinished / 1000 + 1).toString()
            }

            override fun onFinish() {
                countdownTimer = null
                startRecording()
            }
        }.start()
    }

    private fun startRecording() {
        isCountdownRunning = false
        isTestRunning = true
        // Begin the session at the moment recording actually starts (after
        // the 3-s countdown completes), and write the START row immediately
        // so the first SAMPLE row's elapsed_ms is meaningful.
        val s = MotorTestSession(profile, currentSide)
        session = s
        dataManager.writeHandTurningData(s.startRow(sensorColCount))
        btnStartTurning.setTestButtonState(enabled = false, label = "Test Running")
        registerSensors()
        speakCue("Start")

        testTimer = object : CountDownTimer(10000, 100) {
            override fun onTick(millisUntilFinished: Long) {
                findViewById<TextView>(R.id.tvTimer).text = "${millisUntilFinished / 1000}s"
            }

            override fun onFinish() {
                stopRecording()
            }
        }.start()
    }

    private fun stopRecording() {
        isCountdownRunning = false
        isTestRunning = false
        unregisterSensors()
        writeEndRow()
        findViewById<android.view.View>(android.R.id.content)?.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
        speakCue("Stop")
        findViewById<TextView>(R.id.tvTimer).text = "Done!"
        Toast.makeText(this, "Test complete", Toast.LENGTH_SHORT).show()

        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            val forceHand = intent.getStringExtra("EXTRA_HAND")
            if (intent.getBooleanExtra("IS_BATTERY_MODE", false)) {
                setResult(android.app.Activity.RESULT_OK)
                finish()
            } else if (currentSide == Constants.PARTICIPANT_HAND_RIGHT && forceHand == null) {
                promptForLeftHand()
            } else {
                finish()
            }
        }, 1500)
    }

    private fun promptForLeftHand() {
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Right hand complete")
            .setMessage("Now let's test your LEFT hand.\n\nTap OK when you're ready.")
            .setCancelable(false)
            .setPositiveButton("OK — start left hand") { _, _ ->
                val intent = android.content.Intent(this, HandTurningActivity::class.java).apply {
                    putExtra("EXTRA_HAND", Constants.PARTICIPANT_HAND_LEFT)
                }
                startActivity(intent)
                finish()
            }
            .setNegativeButton("Skip") { _, _ -> finish() }
            .show()
    }

    private fun registerSensors() {
        sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let { accel ->
            sensorManager.registerListener(this, accel, SensorManager.SENSOR_DELAY_FASTEST)
        }
        sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)?.let { gyro ->
            sensorManager.registerListener(this, gyro, SensorManager.SENSOR_DELAY_FASTEST)
        }
    }

    private fun unregisterSensors() {
        sensorManager.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (!isTestRunning || event == null) return
        val s = session ?: return

        if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
            accelValues = event.values.clone()
        } else if (event.sensor.type == Sensor.TYPE_GYROSCOPE) {
            gyroValues = event.values.clone()
        }

        val sensorCsv = "${gyroValues[0]},${gyroValues[1]},${gyroValues[2]}," +
                "${accelValues[0]},${accelValues[1]},${accelValues[2]}"
        dataManager.writeHandTurningData(s.sampleRow(sensorCsv))
    }

    /** Idempotent — safe to call from stopRecording AND onDestroy. */
    private fun writeEndRow() {
        val s = session ?: return
        if (endRowWritten) return
        endRowWritten = true
        dataManager.writeHandTurningData(s.endRow(sensorColCount))
    }

    override fun onInit(status: Int) {
        if (isFinishing || isDestroyed) return
        if (status != TextToSpeech.SUCCESS) return
        val tts = textToSpeech ?: return
        val localeStatus = tts.setLanguage(Locale.getDefault())
        isTextToSpeechReady = localeStatus != TextToSpeech.LANG_MISSING_DATA &&
            localeStatus != TextToSpeech.LANG_NOT_SUPPORTED
        if (isTextToSpeechReady) {
            tts.setSpeechRate(0.95f)
        }
    }

    private fun speakCue(cue: String) {
        if (isFinishing || isDestroyed) return
        if (isTextToSpeechReady) {
            textToSpeech?.speak(cue, TextToSpeech.QUEUE_FLUSH, null, "hand_turning_$cue")
            return
        }
        when (cue) {
            "Start" -> toneGenerator.startTone(ToneGenerator.TONE_PROP_BEEP, 200)
            "Stop" -> toneGenerator.startTone(ToneGenerator.TONE_PROP_BEEP2, 800)
            else -> toneGenerator.startTone(ToneGenerator.TONE_PROP_ACK, 150)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onDestroy() {
        isTextToSpeechReady = false
        countdownTimer?.cancel()
        countdownTimer = null
        testTimer?.cancel()
        testTimer = null
        unregisterSensors()
        // If activity is killed mid-trial, still close out the trial cleanly.
        writeEndRow()
        dataManager.closeAll()
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        toneGenerator.release()
        super.onDestroy()
    }
}
