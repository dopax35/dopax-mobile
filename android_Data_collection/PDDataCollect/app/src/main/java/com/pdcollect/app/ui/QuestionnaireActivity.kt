package com.pdcollect.app.ui

import android.os.Bundle
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.util.TimeUtils
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class QuestionnaireActivity : AppCompatActivity() {

    private lateinit var dataManager: DataManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_questionnaire)

        val profile = UserProfile(this)
        dataManager = DataManager(this, profile)

        setupSpinners()

        findViewById<Button>(R.id.btnSaveQuestionnaire).setOnClickListener {
            saveQuestionnaire()
        }
    }

    private fun setupSpinners() {
        val scores = listOf("1", "2", "3", "4", "5")
        val adapter = ArrayAdapter(this, android.R.layout.simple_spinner_item, scores)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)

        findViewById<Spinner>(R.id.spnSleep).adapter = adapter
        findViewById<Spinner>(R.id.spnSmell).adapter = adapter
        findViewById<Spinner>(R.id.spnConst).adapter = adapter
        findViewById<Spinner>(R.id.spnAnxiety).adapter = adapter
        findViewById<Spinner>(R.id.spnDepr).adapter = adapter
    }

    private fun saveQuestionnaire() {
        val q1 = findViewById<EditText>(R.id.editQ1).text.toString().replace(",", ";").trim()
        
        val q2 = getRadioScore(R.id.rgQ2)
        val q3 = getRadioScore(R.id.rgQ3)
        val q4 = getRadioScore(R.id.rgQ4)
        val q5 = getRadioScore(R.id.rgQ5)

        val sleepYes = findViewById<CheckBox>(R.id.cbSleep).isChecked
        val sleepScore = findViewById<Spinner>(R.id.spnSleep).selectedItem.toString()
        
        val smellYes = findViewById<CheckBox>(R.id.cbSmell).isChecked
        val smellScore = findViewById<Spinner>(R.id.spnSmell).selectedItem.toString()
        
        val constYes = findViewById<CheckBox>(R.id.cbConst).isChecked
        val constScore = findViewById<Spinner>(R.id.spnConst).selectedItem.toString()
        
        val anxietyYes = findViewById<CheckBox>(R.id.cbAnxiety).isChecked
        val anxietyScore = findViewById<Spinner>(R.id.spnAnxiety).selectedItem.toString()
        
        val deprYes = findViewById<CheckBox>(R.id.cbDepr).isChecked
        val deprScore = findViewById<Spinner>(R.id.spnDepr).selectedItem.toString()

        val timestamp = System.currentTimeMillis()
        val date = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(timestamp))
        val time = SimpleDateFormat("HH:mm:ss", Locale.US).format(Date(timestamp))
        val row = "$timestamp,$date,$time,$q1,$q2,$q3,$q4,$q5," +
                "$sleepYes,$sleepScore,$smellYes,$smellScore,$constYes,$constScore," +
                "$anxietyYes,$anxietyScore,$deprYes,$deprScore"

        dataManager.writeQuestionnaireData(row)
        Toast.makeText(this, "Questionnaire saved", Toast.LENGTH_SHORT).show()
        setResult(RESULT_OK)
        finish()
    }

    private fun getRadioScore(rgId: Int): Int {
        val rg = findViewById<RadioGroup>(rgId)
        val checkedId = rg.checkedRadioButtonId
        if (checkedId == -1) return 0
        val radioButton = findViewById<RadioButton>(checkedId)
        return radioButton.text.toString().toIntOrNull() ?: 0
    }
}
