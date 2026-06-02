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

        // Render PDF
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
            pdfRenderer = PdfRenderer(parcelFileDescriptor!!)

            val pageCount = pdfRenderer!!.pageCount
            for (i in 0 until pageCount) {
                val page = pdfRenderer!!.openPage(i)
                val bitmap = Bitmap.createBitmap(
                    resources.displayMetrics.densityDpi * page.width / 72,
                    resources.displayMetrics.densityDpi * page.height / 72,
                    Bitmap.Config.ARGB_8888
                )
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
                page.close()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        agreeButton.isEnabled = false

        fun validate() {
            val name = signatureInput.text?.toString()?.trim() ?: ""
            agreeButton.isEnabled = checkbox.isChecked && name.isNotEmpty()
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
            navigateNext()
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        pdfRenderer?.close()
        parcelFileDescriptor?.close()
    }

    private fun navigateNext() {
        val target = if (profile.profileComplete) {
            MainActivity::class.java
        } else {
            ProfileSetupActivity::class.java
        }
        startActivity(Intent(this, target))
        finish()
    }
}
