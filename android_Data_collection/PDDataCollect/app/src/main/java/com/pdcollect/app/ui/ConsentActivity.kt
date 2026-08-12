package com.pdcollect.app.ui

import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.CheckBox
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.pdcollect.app.R
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.widget.ImageView
import android.widget.LinearLayout
import android.text.Editable
import android.text.TextWatcher
import com.google.android.material.textfield.TextInputEditText
import java.io.File
import java.io.FileOutputStream
import com.pdcollect.app.data.UserProfile

class ConsentActivity : AppCompatActivity() {

    private lateinit var profile: UserProfile
    private var pdfRenderer: PdfRenderer? = null
    private var parcelFileDescriptor: ParcelFileDescriptor? = null
    private var consentDocumentLoaded = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        profile = UserProfile(this)

        if (profile.consentGiven) {
            navigateNext()
            return
        }

        setContentView(R.layout.activity_consent)

        val pdfContainer = findViewById<LinearLayout>(R.id.pdfContainer)
        val checkbox = findViewById<CheckBox>(R.id.consentCheckbox)
        val agreeButton = findViewById<Button>(R.id.agreeButton)
        val signatureInput = findViewById<TextInputEditText>(R.id.signatureInput)

        // Render PDF. Pages are scaled to the device's actual screen width in
        // pixels (NOT densityDpi * points/72, which double-applies density and
        // produces multi-hundred-MB bitmaps per page on high-density phones —
        // e.g. ~150MB/page at xxxhdpi for an A4 page, easily OOM-crashing this
        // screen for every new participant on a 3-page consent form).
        var pagesRendered = 0
        try {
            val file = File(cacheDir, "consent_form.pdf")
            if (!file.exists()) {
                val assetStream = assets.open("consent_form.pdf")
                val outputStream = FileOutputStream(file)
                assetStream.copyTo(outputStream)
                assetStream.close()
                outputStream.close()
            }

            parcelFileDescriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            val renderer = PdfRenderer(parcelFileDescriptor!!)
            pdfRenderer = renderer

            // Cap render width at the screen width (already in real device
            // pixels) so we never render at a higher resolution than the
            // screen can even display.
            val targetWidthPx = resources.displayMetrics.widthPixels

            for (i in 0 until renderer.pageCount) {
                try {
                    renderer.openPage(i).use { page ->
                        val scale = targetWidthPx.toFloat() / page.width
                        val widthPx = targetWidthPx
                        val heightPx = (page.height * scale).toInt().coerceAtLeast(1)
                        val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

                        val imageView = ImageView(this).apply {
                            layoutParams = LinearLayout.LayoutParams(
                                LinearLayout.LayoutParams.MATCH_PARENT,
                                LinearLayout.LayoutParams.WRAP_CONTENT
                            ).apply {
                                setMargins(0, 0, 0, 16)
                            }
                            setImageBitmap(bitmap)
                            adjustViewBounds = true
                        }
                        pdfContainer.addView(imageView)
                        pagesRendered++
                    }
                } catch (pageError: Exception) {
                    // Skip this page but keep trying the rest — one corrupt
                    // page shouldn't hide the entire consent document.
                    android.util.Log.e("ConsentActivity", "Failed to render consent page $i", pageError)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ConsentActivity", "Failed to load consent document", e)
        }

        consentDocumentLoaded = pagesRendered > 0
        if (!consentDocumentLoaded) {
            // Never allow silent sign-off on a document the participant could
            // not actually see. Show a clear error and offer a retry instead
            // of leaving a blank box next to an enabled checkbox.
            val errorView = TextView(this).apply {
                text = "We couldn't load the consent document. Please check your storage space " +
                    "and try again, or contact the study team before continuing."
                setTextColor(resources.getColor(R.color.error, theme))
                textSize = 14f
            }
            pdfContainer.addView(errorView)
            checkbox.isEnabled = false
        }

        agreeButton.isEnabled = false

        fun validate() {
            val name = signatureInput.text?.toString()?.trim() ?: ""
            agreeButton.isEnabled = consentDocumentLoaded && checkbox.isChecked && name.isNotEmpty()
        }

        checkbox.setOnCheckedChangeListener { _, _ -> validate() }
        
        signatureInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { validate() }
            override fun afterTextChanged(s: Editable?) {}
        })

        agreeButton.setOnClickListener {
            val name = signatureInput.text?.toString()?.trim() ?: ""
            profile.signatureName = name
            profile.consentTimestamp = System.currentTimeMillis()
            profile.consentGiven = true
            com.pdcollect.app.data.BackendSyncManager.syncConsent(this, name)
            navigateNext()
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        pdfRenderer?.close()
        parcelFileDescriptor?.close()
    }

    private fun navigateNext() {
        val target = if (profile.profileComplete && !profile.needsOnboardingV2) {
            MainActivity::class.java
        } else {
            ProfileSetupActivity::class.java
        }
        startActivity(Intent(this, target))
        finish()
    }
}
