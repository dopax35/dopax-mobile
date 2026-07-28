package com.pdcollect.app.util

import android.content.Context
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.util.Constants

class SetupVerificationManager {

    enum class HealthStatus {
        OPTIMAL,    // Everything configured perfectly
        DEGRADED,   // Missing minor permissions (Notifications)
        CRITICAL    // Missing critical background permissions (Battery, Alarms, Keyboard)
    }

    data class AppHealth(
        val status: HealthStatus,
        val missingItems: List<String>
    )

    companion object {
        fun checkHealth(context: Context): AppHealth {
            val missing = mutableListOf<String>()
            val profile = UserProfile(context)

            // 1. Critical: Battery Optimization
            if (!PermissionUtils.isIgnoringBatteryOptimizations(context)) {
                missing.add("Background reliability")
            }

            // 2. Critical: Exact Alarms (Android 12+)
            if (!PermissionUtils.hasExactAlarmPermission(context)) {
                missing.add("On-time reminders")
            }

            // 3. Critical: PDCollect Keyboard must be enabled when keylogging is on
            if (profile.keyloggingEnabled && !PermissionUtils.isKeyboardEnabled(context)) {
                missing.add("PDCollect Keyboard")
            }

            // 4. Critical: Interaction access (Accessibility) only for background face-distance
            val needsAccessibility =
                profile.passiveCollectionActive &&
                    profile.faceDistanceMode == Constants.FACE_DISTANCE_MODE_ALWAYS
            if (needsAccessibility && !PermissionUtils.isAccessibilityServiceEnabled(context)) {
                missing.add("Interaction access")
            }

            // 5. Critical: Camera (if face distance enabled)
            if (profile.faceDistanceEnabled && !PermissionUtils.hasCameraPermission(context)) {
                missing.add("Camera")
            }

            // 6. Degraded: Notifications
            if (!PermissionUtils.hasNotificationPermission(context)) {
                missing.add("Notifications")
            }

            // 7. Degraded: App Usage Detection — Android periodically revokes this on its own
            // (auto-reset permissions for rarely-opened apps) and there's no ongoing runtime
            // prompt for it, so it must be actively re-checked or app-tagging data silently
            // stops without anyone noticing.
            if (!PermissionUtils.hasUsageStatsPermission(context)) {
                missing.add("App Usage Detection")
            }

            // 8. Degraded: Recording Indicator overlay — same class of silently-revocable
            // permission as usage stats.
            if (!PermissionUtils.canDrawOverlays(context)) {
                missing.add("Recording Indicator")
            }

            val status = when {
                missing.isEmpty() -> HealthStatus.OPTIMAL
                missing.any {
                    it == "Background reliability" ||
                        it == "On-time reminders" ||
                        it == "PDCollect Keyboard" ||
                        it == "Interaction access"
                } -> HealthStatus.CRITICAL
                else -> HealthStatus.DEGRADED
            }

            return AppHealth(status, missing)
        }
    }
}
