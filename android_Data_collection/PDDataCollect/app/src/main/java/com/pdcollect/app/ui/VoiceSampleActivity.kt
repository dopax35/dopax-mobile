package com.pdcollect.app.ui

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.os.CountDownTimer
import android.os.Handler
import android.os.Looper
import android.text.Html
import android.view.View
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.material.button.MaterialButton
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import org.xmlpull.v1.XmlPullParser
import org.xmlpull.v1.XmlPullParserFactory

class VoiceSampleActivity : AppCompatActivity() {

    private lateinit var tvStoryText: TextView
    private lateinit var tvTimer: TextView
    private lateinit var tvStatus: TextView
    private lateinit var btnRecord: MaterialButton
    private lateinit var btnNewStory: MaterialButton
    private lateinit var btnDone: MaterialButton
    private lateinit var progressStory: ProgressBar

    private lateinit var dataManager: DataManager
    private lateinit var profile: UserProfile

    private var currentHeadline: String = ""

    private var recorder: MediaRecorder? = null
    private var currentOutputFile: File? = null
    private var isRecording = false
    private var recordingStartMs = 0L

    private var countDownTimer: CountDownTimer? = null

    private val requestPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) startRecording()
        else Toast.makeText(this, "Microphone permission required.", Toast.LENGTH_LONG).show()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_voice_sample)
        supportActionBar?.title = "Voice Sample"
        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        tvStoryText = findViewById(R.id.tvStoryText)
        tvTimer = findViewById(R.id.tvTimer)
        tvStatus = findViewById(R.id.tvStatus)
        btnRecord = findViewById(R.id.btnRecord)
        btnNewStory = findViewById(R.id.btnNewStory)
        btnDone = findViewById(R.id.btnDone)
        progressStory = findViewById(R.id.progressStory)

        profile = UserProfile(this)
        dataManager = DataManager(this, profile)

        btnRecord.setOnClickListener {
            if (isRecording) stopRecording() else checkPermissionAndRecord()
        }
        btnNewStory.setOnClickListener { if (!isRecording) loadStory() }
        btnDone.setOnClickListener { finish() }
        findViewById<MaterialButton>(R.id.btnExit).setOnClickListener {
            if (isRecording) stopRecording()
            finish()
        }

        loadStory()
    }

    override fun onSupportNavigateUp(): Boolean {
        if (isRecording) stopRecording()
        finish()
        return true
    }

    // ── Story loading ─────────────────────────────────────────────────────────

    private fun loadStory() {
        tvStoryText.text = "טוען כתבה..."
        progressStory.visibility = View.VISIBLE
        btnNewStory.isEnabled = false
        btnDone.visibility = View.GONE
        tvStatus.text = ""

        Thread {
            val (headline, body) = fetchLongHebrewStory()
            Handler(Looper.getMainLooper()).post {
                if (isFinishing || isDestroyed) return@post
                progressStory.visibility = View.GONE
                btnNewStory.isEnabled = true
                currentHeadline = headline
                tvStoryText.text = "$headline\n\n$body"
            }
        }.start()
    }

    private fun fetchLongHebrewStory(): Pair<String, String> {
        return try {
            val url = URL("https://www.ynet.co.il/Integration/StoryRss2.xml")
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 10_000
            conn.readTimeout = 10_000
            conn.setRequestProperty("User-Agent", "PDCollect/1.0")
            conn.connect()

            if (conn.responseCode != HttpURLConnection.HTTP_OK) {
                conn.disconnect()
                return randomFallback()
            }

            data class RssItem(val title: String, val description: String)

            val items = mutableListOf<RssItem>()
            val factory = XmlPullParserFactory.newInstance()
            val parser = factory.newPullParser()
            parser.setInput(conn.inputStream, "UTF-8")

            var inItem = false
            var title = ""
            var description = ""
            var eventType = parser.eventType

            while (eventType != XmlPullParser.END_DOCUMENT && items.size < 30) {
                when (eventType) {
                    XmlPullParser.START_TAG -> when (parser.name) {
                        "item" -> { inItem = true; title = ""; description = "" }
                        "title" -> if (inItem) title = parser.nextText().trim()
                        "description" -> if (inItem) description = stripHtml(parser.nextText().trim())
                    }
                    XmlPullParser.END_TAG -> if (parser.name == "item" && inItem) {
                        if (title.isNotBlank() && description.length > 40) {
                            items.add(RssItem(title, description))
                        }
                        inItem = false
                    }
                }
                eventType = parser.next()
            }
            conn.disconnect()

            if (items.isEmpty()) return randomFallback()

            // Pick a random primary story; extend significantly to ensure scrolling is required
            items.shuffle()
            val primary = items[0]
            var body = primary.description

            // Add up to 3 secondary stories to ensure plenty of text for 60 seconds
            for (i in 1 until minOf(4, items.size)) {
                val next = items[i]
                body = "$body\n\n${next.title}\n\n${next.description}"
            }

            primary.title to body

        } catch (e: Exception) {
            android.util.Log.w("VoiceSample", "RSS fetch failed", e)
            randomFallback()
        }
    }

    private fun stripHtml(html: String): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            Html.fromHtml(html, Html.FROM_HTML_MODE_LEGACY).toString().trim()
        } else {
            @Suppress("DEPRECATION")
            Html.fromHtml(html).toString().trim()
        }
    }

    private fun randomFallback(): Pair<String, String> {
        val fallbacks = listOf(
            "מזג האוויר בישראל" to """
מזג האוויר בישראל צפוי להיות נעים ומתון בימים הקרובים. הטמפרטורות יהיו ממוצעות לעונה, עם ערכים שבין שמונה עשרה לעשרים וחמש מעלות צלזיוס. בשעות הצהריים צפויה התחממות קלה, בעוד שהלילות יהיו קרירים ונוחים.

רוחות קלות עד בינוניות צפויות לנשוב ממערב, ולהביא עימן אוויר ים תיכוני רענן ונקי. הלחות תהיה בינונית, כך שלא ייגרם אי נוחות משמעותי. שמיים בהירים צפויים ברוב שעות היום, עם ביטוי ענן חלקי בעיקר בצפון הארץ.

לאחר מספר ימים של יציבות, עשוי להגיע שינוי קל בסוף השבוע, עם עלייה קלה ברמות הלחות ואפשרות לעננות בצפון. תושבי השרון והגליל מתבקשים לשים לב לעדכוני מזג האוויר.

שירות מטאורולוגי ישראל ממליץ לנצל את מזג האוויר הנוח לפעילויות חוץ ולטיולים בטבע, תוך שמירה על שתיית נוזלים מספקת. ילדים וקשישים מתבקשים להיזהר משינויים פתאומיים בטמפרטורה בשעות הבוקר המוקדמות.
            """.trimIndent(),

            "חדשות מהשוק הישראלי" to """
שוק המניות הישראלי סגר את המסחר בשבוע החולף עם תוצאות מעורבות. מדד תל אביב מאה עלה בכחצי אחוז, בעוד שמדד תל אביב שלושים וחמישה ירד בשיעור קטן. מגזר הטכנולוגיה הפגין יציבות יחסית, עם עליות קלות בחברות הסייבר והתוכנה המובילות.

נתוני הייצוא החודש הצביעו על מגמת שיפור בענפי הייטק ופרמצבטיקה. יצוא שירותי הטכנולוגיה עלה בשמונה אחוזים בהשוואה לתקופה המקבילה אשתקד. כלכלנים מציינים כי הנתונים מצביעים על חוסן כלכלי בולט, על אף האתגרים הגיאופוליטיים.

בנק ישראל פרסם את הדוח הרבעוני שלו, בו הוא מסמן כי האינפלציה נמצאת במגמת ירידה הדרגתית. הריבית צפויה להישאר ללא שינוי בפגישה הבאה של הוועדה המוניטרית. ממשלת ישראל מקדמת מספר תוכניות לעידוד השקעות זרות ותמיכה ביזמים צעירים.

שוק הנדל"ן ממשיך להציג ביקושים גבוהים, אם כי ניכרת עלייה בהיצע הדירות החדשות. מחירי השכירות בערים הגדולות יציבים יחסית, לאחר שנים של עליות חדות. כלכלנים מייחסים זאת לשיפור בתנאי המשכנתא ולבנייה מואצת בפריפריה.
            """.trimIndent(),

            "ספורט ישראלי וספורטאים מצטיינים" to """
נבחרת ישראל בכדורגל ממשיכה בהכנות האינטנסיביות לקראת משחקי הבית הקרובים. הסלקטור הלאומי הכריז על הרכב הנבחרת, הכולל מספר שחקנים צעירים ומבטיחים לצד הוותיקים המנוסים. האימונים מתקיימים בסמנה מרובה פגישות אינטנסיביות, עם דגש על משחק תחתון וכיסוי הגנתי.

בכדורסל, מכבי תל אביב מציגה עונה מרשימה בליגת יורוליג. הקבוצה ניצחה בארבעת משחקיה האחרונים וחיזקה את מקומה בשמונה הגדולות. הקהל הממלא את היכל מנורה מבטיח מדי משחק מתנהג בהתלהבות רבה, ותומך בשחקנים בצורה יוצאת דופן.

בספורט מים, שחיינים ישראלים שברו שישה שיאים ארציים בתחרות הלאומית שנערכה בבאר שבע. הנבחרת הצעירה מביאה ביצועים מעוררי התפעלות, ומגדילה לקוות לתוצאות מפתיעות באליפות אירופה הקרובה.

ספורטאים ישראלים בענפי הלחימה גם הם מוסיפים גאווה למדינה, עם זכייה במדליות בינלאומיות. הג'ודוקאים, האופניסטים ורוכבי האופניים מציגים עוצמה בתחרויות בינלאומיות, ומגייסים מעריצים רבים ברחבי הארץ.
            """.trimIndent(),

            "טכנולוגיה, בינה מלאכותית וחדשנות ישראלית" to """
חברות טכנולוגיה ישראליות ממשיכות לרשום הצלחות בינלאומיות מרשימות בתחום הבינה המלאכותית. השנה האחרונה ראתה השקות של מוצרים פורצי דרך במגוון תחומים, החל מרפואה ועד חקלאות. ישראל נחשבת כיום לאחת ממדינות הסטארטאפ המובילות בעולם.

בתחום הסייבר, חברות ביטחון סייבר ישראליות מגייסות השקעות עתק מקרנות בינלאומיות מובילות. הטכנולוגיות שפותחו בישראל מגינות על תשתיות קריטיות ברחבי העולם. המדינה נחשבת ל"ואדי הסיליקון של הסייבר", ומאות מומחים מגיעים כל שנה לרכוש ידע בתעשייה המקומית.

בתחום הבינה המלאכותית הרפואית, מספר חברות ישראליות פיתחו אלגוריתמים לאיתור מוקדם של מחלות. מערכות אלה כבר פועלות בבתי חולים בארצות הברית, גרמניה ויפן, ומסייעות לרופאים לאבחן מחלות מוקדם יותר.

האקדמיה הישראלית גם היא שותפה פעילה בפיתוח הטכנולוגי. אוניברסיטת תל אביב, הטכניון ועוד מספר מוסדות מחקר מובילים פרויקטים בינלאומיים רחבי היקף. שיתופי פעולה עם חברות טכנולוגיה ענקיות כגוגל, מיקרוסופט ואמזון מגבירים את עוצמת המחקר הישראלי.
            """.trimIndent(),

            "חינוך ורווחה חברתית בישראל" to """
מערכת החינוך הישראלית עוברת שינויים משמעותיים במגמה להתאים את עצמה לעידן הדיגיטלי. משרד החינוך פתח השנה בתוכנית לאומית להטמעת בינה מלאכותית בבתי ספר, מגן הילדים ועד כיתה יב. כשלושים אלף מורים קיבלו הכשרה מתאימה לשימוש בכלים הדיגיטליים החדשניים.

התלמידים מגלים עניין רב בלמידה מבוססת פרויקטים וחשיבה יצירתית. שיעורי ה-STEM, הכוללים מדע, טכנולוגיה, הנדסה ומתמטיקה, זוכים לפופולריות גוברת. תחרויות ממציאים לצעירים מושכות משתתפים ממחוזות שונים ברחבי הארץ.

בתחום הרווחה החברתית, המדינה מגדילה השנה את תקציבי השירות לאוכלוסיות בסיכון. פעילויות מתנדבים ועמותות מתרחבות בעיר ובפריפריה, עם מאות פרויקטים חברתיים חדשים. אנשים מכל הגילאים יוצאים להתנדב ולסייע לקשישים, ילדים ומשפחות נזקקות.

תוכניות לאומיות לטיפול בתלמידים עם לקויות למידה זוכות להרחבה ולתוספת תקציבית. מומחים בתחום מדגישים כי זיהוי מוקדם ותמיכה מתאימה יכולים לשנות את חייהם של ילדים רבים. ישראל נמצאת בחזית של מחקר ותמיכה ילדים עם אוטיזם, דיסלקציה ולקויות אחרות.
            """.trimIndent()
        )
        return fallbacks.random()
    }

    // ── Recording ─────────────────────────────────────────────────────────────

    private fun checkPermissionAndRecord() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            == PackageManager.PERMISSION_GRANTED
        ) {
            startRecording()
        } else {
            requestPermission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    private fun startRecording() {
        val timestamp = System.currentTimeMillis()
        val voiceDir = File(dataManager.getDayDir(), "voice")
        voiceDir.mkdirs()
        val outputFile = File(voiceDir, "voice_${timestamp}.m4a")
        currentOutputFile = outputFile
        recordingStartMs = timestamp

        try {
            val rec = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }
            rec.setAudioSource(MediaRecorder.AudioSource.MIC)
            rec.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            rec.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            rec.setAudioSamplingRate(44100)
            rec.setAudioEncodingBitRate(96_000)
            rec.setOutputFile(outputFile.absolutePath)
            rec.prepare()
            rec.start()
            recorder = rec
            isRecording = true

            btnRecord.text = "Stop Recording"
            tvStatus.text = "Recording in progress..."
            tvTimer.visibility = View.VISIBLE
            btnNewStory.isEnabled = false
            btnDone.visibility = View.GONE

            startCountDown()
        } catch (e: Exception) {
            android.util.Log.e("VoiceSample", "Failed to start recording", e)
            Toast.makeText(this, "Could not start recording: ${e.message}", Toast.LENGTH_LONG).show()
            cleanupRecorder()
        }
    }

    private fun startCountDown() {
        countDownTimer?.cancel()
        countDownTimer = object : CountDownTimer(60_000L, 1000L) {
            override fun onTick(millisUntilFinished: Long) {
                val secs = millisUntilFinished / 1000
                tvTimer.text = String.format(Locale.US, "%02d:%02d", secs / 60, secs % 60)
            }
            override fun onFinish() {
                tvTimer.text = "00:00"
                stopRecording()
            }
        }.start()
    }

    private fun stopRecording() {
        countDownTimer?.cancel()
        countDownTimer = null

        val durationMs = System.currentTimeMillis() - recordingStartMs

        runCatching {
            recorder?.stop()
        }.onFailure {
            android.util.Log.w("VoiceSample", "Stop failed (likely too short)", it)
        }
        runCatching {
            recorder?.release()
        }
        recorder = null
        isRecording = false

        if (isFinishing || isDestroyed) return

        btnRecord.text = "Record Again"
        tvTimer.visibility = View.GONE
        btnNewStory.isEnabled = true

        val outputFile = currentOutputFile
        if (outputFile != null && outputFile.exists() && outputFile.length() > 0) {
            val secs = durationMs / 1000
            tvStatus.text = "Saved (${secs}s) — tap Record Again or Done"
            logVoiceEntry(outputFile.name, currentHeadline, durationMs)
            btnDone.visibility = View.VISIBLE
        } else {
            tvStatus.text = "Recording too short — try again"
            outputFile?.delete()
        }
        currentOutputFile = null
    }

    private fun logVoiceEntry(filename: String, headline: String, durationMs: Long) {
        val timestamp = System.currentTimeMillis()
        val safeHeadline = headline.replace("\"", "\"\"")
        val row = "$timestamp,\"$filename\",\"$safeHeadline\",$durationMs"
        dataManager.writeVoiceLogData(row)
    }

    private fun cleanupRecorder() {
        countDownTimer?.cancel()
        countDownTimer = null
        try { recorder?.release() } catch (_: Exception) {}
        recorder = null
        isRecording = false
        btnRecord.text = "Start Recording"
        tvTimer.visibility = View.GONE
        btnNewStory.isEnabled = true
    }

    override fun onPause() {
        super.onPause()
        if (isRecording) stopRecording()
    }

    override fun onDestroy() {
        cleanupRecorder()
        super.onDestroy()
    }
}
