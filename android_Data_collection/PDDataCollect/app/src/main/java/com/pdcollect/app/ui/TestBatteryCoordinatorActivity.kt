package com.pdcollect.app.ui

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.pdcollect.app.util.Constants

class TestBatteryCoordinatorActivity : AppCompatActivity() {

    private val STAGE_FT_RIGHT = 1
    private val STAGE_FT_LEFT = 2
    private val STAGE_HT_RIGHT = 3
    private val STAGE_HT_LEFT = 4
    private val STAGE_ST_RIGHT = 5
    private val STAGE_ST_LEFT = 6
    private val STAGE_LA_RIGHT = 7
    private val STAGE_LA_LEFT = 8
    private val STAGE_TMT = 9
    private val STAGE_QUESTIONNAIRE = 10

    private var currentStage = 1

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Hidden UI, immediately routes if this is NOT a recreation
        if (savedInstanceState == null) {
            routeStage()
        } else {
            currentStage = savedInstanceState.getInt("KEY_STAGE", 1)
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putInt("KEY_STAGE", currentStage)
    }

    private fun routeStage() {
        val intent = when (currentStage) {
            STAGE_FT_RIGHT -> Intent(this, FingerTappingActivity::class.java).apply { putExtra("EXTRA_HAND", "Right") }
            STAGE_FT_LEFT -> Intent(this, FingerTappingActivity::class.java).apply { putExtra("EXTRA_HAND", "Left") }
            STAGE_HT_RIGHT -> Intent(this, HandTurningActivity::class.java).apply { putExtra("EXTRA_HAND", "Right") }
            STAGE_HT_LEFT -> Intent(this, HandTurningActivity::class.java).apply { putExtra("EXTRA_HAND", "Left") }
            STAGE_ST_RIGHT -> Intent(this, SpiralTracingActivity::class.java).apply { putExtra("EXTRA_HAND", "Right") }
            STAGE_ST_LEFT -> Intent(this, SpiralTracingActivity::class.java).apply { putExtra("EXTRA_HAND", "Left") }
            STAGE_LA_RIGHT -> Intent(this, LegAgilityActivity::class.java).apply { putExtra("EXTRA_LEG", "Right") }
            STAGE_LA_LEFT -> Intent(this, LegAgilityActivity::class.java).apply { putExtra("EXTRA_LEG", "Left") }
            STAGE_TMT -> Intent(this, TrailMakingTestActivity::class.java)
            STAGE_QUESTIONNAIRE -> Intent(this, QuestionnaireActivity::class.java)
            else -> {
                (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .cancel(Constants.NOTIFICATION_ID_BATTERY_REMINDER)
                Toast.makeText(this, "Test Battery Complete! Great job!", Toast.LENGTH_LONG).show()
                val mainIntent = Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                startActivity(mainIntent)
                finish()
                return
            }
        }
        intent.putExtra("IS_BATTERY_MODE", true)
        // StartActivityForResult is deprecated but still works fine for the current target;
        // The more modern way would be ActivityResultLauncher, but for a coordinator like this, 
        // the simplicity of one request code is cleaner.
        startActivityForResult(intent, 1000)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1000) {
            // Questionnaire advances regardless of result — motor data is already saved
            // and the questionnaire is optional. All other stages require RESULT_OK.
            if (resultCode == RESULT_OK || currentStage >= STAGE_QUESTIONNAIRE) {
                currentStage++
                routeStage()
            } else {
                // Cancelled or back button pressed during a motor test
                Toast.makeText(this, "Battery Sequence Cancelled", Toast.LENGTH_SHORT).show()
                val mainIntent = Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                startActivity(mainIntent)
                finish()
            }
        }
    }
}
