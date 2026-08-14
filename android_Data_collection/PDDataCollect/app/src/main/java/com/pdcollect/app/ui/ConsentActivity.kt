package com.pdcollect.app.ui

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import com.google.android.material.button.MaterialButton
import com.pdcollect.app.R
import com.pdcollect.app.data.BackendSyncManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.ui.view.SignaturePadView
import android.widget.ImageView
import java.io.File
import java.io.FileOutputStream

class ConsentActivity : AppCompatActivity() {

    private lateinit var profile: UserProfile
    private var pdfRenderer: PdfRenderer? = null
    private var parcelFileDescriptor: ParcelFileDescriptor? = null
    private var consentDocumentLoaded = false
    private var consentLocale = "en"

    private lateinit var pdfContainer: LinearLayout
    private lateinit var consentContentContainer: LinearLayout
    private lateinit var subtitleView: TextView
    private lateinit var checkbox: CheckBox
    private lateinit var agreeButton: MaterialButton
    private lateinit var signatureInput: EditText
    private lateinit var signaturePad: SignaturePadView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        profile = UserProfile(this)

        if (profile.consentGiven) {
            navigateNext()
            return
        }

        setContentView(R.layout.activity_consent)

        pdfContainer = findViewById(R.id.pdfContainer)
        consentContentContainer = findViewById(R.id.consentContentContainer)
        subtitleView = findViewById(R.id.tvConsentSubtitle)
        checkbox = findViewById(R.id.consentCheckbox)
        agreeButton = findViewById(R.id.agreeButton)
        signatureInput = findViewById(R.id.signatureInput)
        signaturePad = findViewById(R.id.signaturePad)

        consentLocale = profile.consentLocale.ifBlank { "en" }
        if (!signatureInput.text.isNullOrBlank()) {
            signatureInput.setText(profile.signatureName)
        }

        findViewById<TextView>(R.id.chipLanguage).setOnClickListener { toggleLocale() }
        findViewById<TextView>(R.id.btnClearSignature).setOnClickListener {
            signaturePad.clear()
            validate()
        }
        signaturePad.onSignatureChanged = { validate() }

        loadConsentPdf()
        applyLocaleChrome()

        agreeButton.isEnabled = false

        checkbox.setOnCheckedChangeListener { _, _ -> validate() }
        signatureInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { validate() }
            override fun afterTextChanged(s: Editable?) {}
        })

        agreeButton.setOnClickListener {
            val name = signatureInput.text?.toString()?.trim().orEmpty()
            val signatureImage = signaturePad.exportPngBase64().orEmpty()
            profile.signatureName = name
            profile.consentSignatureImage = signatureImage
            profile.consentLocale = consentLocale
            profile.consentTimestamp = System.currentTimeMillis()
            profile.consentGiven = true
            BackendSyncManager.syncConsent(
                context = this,
                signatureName = name,
                signatureImage = signatureImage.ifBlank { null },
                documentLocale = consentLocale,
            )
            navigateNext()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        closePdfRenderer()
    }

    private fun toggleLocale() {
        consentLocale = if (consentLocale == "en") "he" else "en"
        applyLocaleChrome()
        loadConsentPdf()
        validate()
    }

    private fun applyLocaleChrome() {
        val languageLabel = if (consentLocale == "he") "Hebrew" else "English"
        subtitleView.text = "Please read and sign. Presented in $languageLabel."

        val direction = if (consentLocale == "he") View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
        ViewCompat.setLayoutDirection(consentContentContainer, direction)
        consentContentContainer.textDirection =
            if (consentLocale == "he") View.TEXT_DIRECTION_RTL else View.TEXT_DIRECTION_LTR
    }

    private fun loadConsentPdf() {
        closePdfRenderer()
        pdfContainer.removeAllViews()
        consentDocumentLoaded = false

        var pagesRendered = 0
        try {
            val assetName = consentPdfAssetName()
            val file = File(cacheDir, "consent_${consentLocale}.pdf")
            if (!file.exists()) {
                assets.open(assetName).use { assetStream ->
                    FileOutputStream(file).use { outputStream ->
                        assetStream.copyTo(outputStream)
                    }
                }
            }

            parcelFileDescriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            val renderer = PdfRenderer(parcelFileDescriptor!!)
            pdfRenderer = renderer

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
                                LinearLayout.LayoutParams.WRAP_CONTENT,
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
                    android.util.Log.e("ConsentActivity", "Failed to render consent page $i", pageError)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ConsentActivity", "Failed to load consent document", e)
        }

        consentDocumentLoaded = pagesRendered > 0
        if (!consentDocumentLoaded) {
            val errorView = TextView(this).apply {
                text = "We couldn't load the consent document. Please check your storage space " +
                    "and try again, or contact the study team before continuing."
                setTextColor(resources.getColor(R.color.error, theme))
                textSize = 14f
            }
            pdfContainer.addView(errorView)
            checkbox.isEnabled = false
        } else {
            checkbox.isEnabled = true
        }
    }

    private fun consentPdfAssetName(): String {
        val hebrewAsset = "consent_form_he.pdf"
        return if (consentLocale == "he" && assetExists(hebrewAsset)) {
            hebrewAsset
        } else {
            "consent_form.pdf"
        }
    }

    private fun assetExists(name: String): Boolean = try {
        assets.open(name).close()
        true
    } catch (_: Exception) {
        false
    }

    private fun closePdfRenderer() {
        pdfRenderer?.close()
        pdfRenderer = null
        parcelFileDescriptor?.close()
        parcelFileDescriptor = null
    }

    private fun validate() {
        val name = signatureInput.text?.toString()?.trim().orEmpty()
        agreeButton.isEnabled = consentDocumentLoaded &&
            checkbox.isChecked &&
            name.isNotEmpty() &&
            !signaturePad.isEmpty()
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
