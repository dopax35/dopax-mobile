package com.pdcollect.app.util

import android.content.Context
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.util.Constants

class SetupVerificationManager {

    enum class HealthStatus {
        OPTIMAL,    // Everything configured perfectly
        DEGRADED,   // Missing minor permissions (Notifications)
        CRITICAL    // Missing critical background permissions (Battery, Alarms, Accessibility)
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

            // 3. Critical: Interaction access if needed for keylogging or face-distance
            val needsAccessibility =
                profile.keyloggingEnabled ||
                    (profile.passiveCollectionActive &&
                        profile.faceDistanceMode == Constants.FACE_DISTANCE_MODE_ALWAYS)
            if (needsAccessibility && !PermissionUtils.isAccessibilityServiceEnabled(context)) {
                missing.add("Accessibility permission")
            }

            // 4. Critical: Camera (if face distance enabled)
            if (profile.faceDistanceEnabled && !PermissionUtils.hasCameraPermission(context)) {
                missing.add("Camera")
            }

            // 5. Degraded: Notifications
            if (!PermissionUtils.hasNotificationPermission(context)) {
                missing.add("Notifications")
            }

            val status = when {
                missing.isEmpty() -> HealthStatus.OPTIMAL
                missing.any {
                    it == "Background reliability" ||
                        it == "On-time reminders" ||
                        it == "Interaction access"
                } -> HealthStatus.CRITICAL
                else -> HealthStatus.DEGRADED
            }

            return AppHealth(status, missing)
        }
    }
}
