package com.pdcollect.app.service

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.data.model.AppEvent
import com.pdcollect.app.data.model.KeyEvent
import com.pdcollect.app.data.model.TouchEvent
import com.pdcollect.app.util.Constants
import com.pdcollect.app.util.TimeUtils

class DataAccessibilityService : AccessibilityService() {
    private val TAG = "DataAccessSvc"
    private lateinit var dataManager: DataManager
    private lateinit var profile: UserProfile
    private var currentPackage = ""
    private var lastTextLength = 0

    // Hard denylist: never log keystrokes from these packages, even if keylogging
    // is enabled. Covers IMEs, password managers, common messengers and the
    // Play Store. Defense-in-depth on top of the per-field password check below.
    private val sensitivePackages = setOf(
        "com.lastpass.lpandroid",
        "com.dashlane",
        "com.x8bit.bitwarden",
        "com.azure.authenticator",
        "com.onepassword.android",
        "com.android.systemui",
        "android",
        "com.google.android.inputmethod.latin",
        "com.samsung.android.honeyboard",
        "com.whatsapp",
        "org.telegram.messenger",
        "com.google.android.apps.messaging",
        "com.signal",
        "com.android.vending"
    )

    override fun onCreate() {
        super.onCreate()
        profile = UserProfile(this)
        dataManager = DataManager(this, profile)
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceInfo = serviceInfo.apply {
            eventTypes = AccessibilityEvent.TYPE_VIEW_CLICKED or
                    AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED or
                    AccessibilityEvent.TYPE_VIEW_SCROLLED or
                    AccessibilityEvent.TYPE_VIEW_FOCUSED or
                    AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                    AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            notificationTimeout = 50
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        val keyloggingEnabled = profile.keyloggingEnabled
        val needsForegroundTracking =
            profile.passiveCollectionActive &&
                profile.faceDistanceMode == Constants.FACE_DISTANCE_MODE_ALWAYS
        val shouldHandleWindowChange =
            event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && needsForegroundTracking
        if (!keyloggingEnabled && !shouldHandleWindowChange) return

        val timestamp = TimeUtils.currentTimeMs()
        val pkg = event.packageName?.toString() ?: ""
        if (Log.isLoggable(TAG, Log.DEBUG)) {
            Log.d(TAG, "onAccessibilityEvent: type=${event.eventType}, pkg=$pkg")
        }

        when (event.eventType) {
            AccessibilityEvent.TYPE_VIEW_CLICKED -> {
                if (keyloggingEnabled && pkg !in sensitivePackages) {
                    handleClick(event, timestamp, pkg)
                }
            }
            AccessibilityEvent.TYPE_VIEW_FOCUSED -> {
                if (keyloggingEnabled && pkg !in sensitivePackages) {
                    handleFocus(event, timestamp, pkg)
                }
            }
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> {
                if (keyloggingEnabled && pkg !in sensitivePackages) {
                    handleTextChanged(event, timestamp, pkg)
                }
            }
            AccessibilityEvent.TYPE_VIEW_SCROLLED -> {
                if (keyloggingEnabled && pkg !in sensitivePackages) {
                    handleScroll(event, timestamp, pkg)
                }
            }
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> handleWindowChange(event, timestamp, pkg)
            else -> {}
        }
    }

    private fun handleClick(event: AccessibilityEvent, timestamp: Long, pkg: String) {
        val source = event.source ?: return
        try {
            val bounds = android.graphics.Rect()
            source.getBoundsInScreen(bounds)
            val touchEvent = TouchEvent(
                timestampMs = timestamp,
                eventType = "click",
                x = bounds.centerX(),
                y = bounds.centerY(),
                sourceApp = pkg
            )
            dataManager.writeTouchEvent(touchEvent.toCsvRow())
        } finally {
            source.recycle()
        }
    }

    private fun handleFocus(event: AccessibilityEvent, timestamp: Long, pkg: String) {
        val source = event.source ?: return
        try {
            val bounds = android.graphics.Rect()
            source.getBoundsInScreen(bounds)
            val touchEvent = TouchEvent(
                timestampMs = timestamp,
                eventType = "focus",
                x = bounds.centerX(),
                y = bounds.centerY(),
                sourceApp = pkg
            )
            dataManager.writeTouchEvent(touchEvent.toCsvRow())
        } finally {
            source.recycle()
        }
    }

    private fun handleTextChanged(event: AccessibilityEvent, timestamp: Long, pkg: String) {
        // PRIVACY: never log the actual text. We use lengths only to detect
        // forward typing vs. backspace, then write a non-identifying key class.
        val source = event.source
        try {
            // Skip password fields — Android marks them via isPassword(); also
            // catch text-input fields whose input type is a variation of password.
            if (source?.isPassword == true) return
            val inputType = source?.inputType ?: 0
            val variation = inputType and android.text.InputType.TYPE_MASK_VARIATION
            val isPasswordVariation = variation == android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                    variation == android.text.InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD ||
                    variation == android.text.InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                    variation == android.text.InputType.TYPE_NUMBER_VARIATION_PASSWORD
            if (isPasswordVariation) return

            val newLength = event.text?.sumOf { it.length } ?: 0
            val isBackspace = newLength < lastTextLength
            val keyClass = if (isBackspace) {
                "backspace"
            } else if (newLength > lastTextLength) {
                // Classify only the most recently added character via its addedCount
                val added = event.addedCount.coerceAtLeast(1)
                val text = event.text?.joinToString("") ?: ""
                val ch = if (text.isNotEmpty()) text[(text.length - added).coerceAtLeast(0)] else ' '
                KeyEvent.classify(ch)
            } else {
                "other"
            }
            lastTextLength = newLength

            val keyEvent = KeyEvent(
                timestampMs = timestamp,
                keyClass = keyClass,
                isBackspace = isBackspace,
                sourceApp = pkg
            )
            dataManager.writeKeyEvent(keyEvent.toCsvRow())
        } finally {
            source?.recycle()
        }
    }

    private fun handleScroll(event: AccessibilityEvent, timestamp: Long, pkg: String) {
        val touchEvent = TouchEvent(
            timestampMs = timestamp,
            eventType = "scroll",
            x = event.scrollX,
            y = event.scrollY,
            sourceApp = pkg
        )
        dataManager.writeTouchEvent(touchEvent.toCsvRow())
    }

    private fun handleWindowChange(event: AccessibilityEvent, timestamp: Long, pkg: String) {
        if (pkg != currentPackage && pkg.isNotEmpty()) {
            val shouldPersistAppEvents = profile.keyloggingEnabled
            if (shouldPersistAppEvents && currentPackage.isNotEmpty()) {
                val closeEvent = AppEvent(timestamp, "close", currentPackage, "")
                dataManager.writeAppEvent(closeEvent.toCsvRow())
            }
            currentPackage = pkg
            if (shouldPersistAppEvents) {
                val className = event.className?.toString() ?: ""
                val openEvent = AppEvent(timestamp, "open", pkg, className)
                dataManager.writeAppEvent(openEvent.toCsvRow())
            }

            // Notify FaceDistanceService (and any other local listener) about
            // the new foreground package so it can gate distance sampling.
            LocalBroadcastManager.getInstance(this).sendBroadcast(
                Intent(Constants.ACTION_FOREGROUND_APP_CHANGED).apply {
                    putExtra(Constants.EXTRA_FOREGROUND_PACKAGE, pkg)
                }
            )
        }
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        dataManager.closeAll()
        super.onDestroy()
    }
}
