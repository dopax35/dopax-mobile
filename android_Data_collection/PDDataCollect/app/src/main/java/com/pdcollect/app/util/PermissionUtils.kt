package com.pdcollect.app.util

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.AppOpsManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import com.pdcollect.app.service.DataAccessibilityService
import java.util.Locale

object PermissionUtils {

    fun isAccessibilityServiceEnabled(context: Context): Boolean {
        val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        val enabledServices = am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
        for (service in enabledServices) {
            if (service.resolveInfo.serviceInfo.packageName == context.packageName &&
                service.resolveInfo.serviceInfo.name == DataAccessibilityService::class.java.name) {
                return true
            }
        }
        return false
    }

    fun hasUsageStatsPermission(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, 
            Process.myUid(), context.packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun canDrawOverlays(context: Context): Boolean {
        return Settings.canDrawOverlays(context)
    }

    fun hasCameraPermission(context: Context): Boolean {
        return androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.CAMERA) == 
                android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    fun hasExactAlarmPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            return am.canScheduleExactAlarms()
        }
        return true
    }

    fun hasNotificationPermission(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.POST_NOTIFICATIONS) == 
                    android.content.pm.PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    // Settings Navigation

    fun openExactAlarmSettings(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            launchSettingsIntent(context, Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = Uri.parse("package:${context.packageName}")
            }, fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
            })
        }
    }

    fun openAccessibilitySettings(context: Context) {
        launchSettingsIntent(context, Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
    }

    fun openUsageAccessSettings(context: Context) {
        launchSettingsIntent(context, Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
    }

    fun openOverlaySettings(context: Context) {
        launchSettingsIntent(
            context,
            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}")),
            fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
            }
        )
    }

    fun openNotificationSettings(context: Context) {
        val appSpecific = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        }
        val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
        }
        launchSettingsIntent(context, appSpecific, fallback)
    }

    fun openBatteryOptimizationSettings(context: Context) {
        val requestIntent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${context.packageName}")
        }
        val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        if (isIgnoringBatteryOptimizations(context)) {
            launchSettingsIntent(context, fallback)
        } else {
            launchSettingsIntent(context, requestIntent, fallback)
        }
    }

    fun openAppSettings(context: Context) {
        launchSettingsIntent(context, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
        })
    }

    fun accessibilitySettingsPathLabel(): String {
        val manufacturer = Build.MANUFACTURER.orEmpty().lowercase(Locale.US)
        return when {
            manufacturer.contains("samsung") ->
                "Samsung: Settings > Accessibility > Installed apps > DopaX Data Logger"
            manufacturer.contains("google") ->
                "Pixel: Settings > Accessibility > Downloaded apps or Installed apps > DopaX Data Logger"
            else ->
                "Android: Settings > Accessibility > Installed apps, Downloaded apps, or Services > DopaX Data Logger"
        }
    }

    fun accessibilitySettingsHelp(featureSummary: String): String {
        return buildString {
            append(featureSummary)
            append("\n\n")
            append("DopaX cannot turn this switch on or off itself. Use this path on your phone:\n")
            append(accessibilitySettingsPathLabel())
            append("\n\n")
            append("Open that page and use the DopaX Data Logger switch to enable or disable access.")
        }
    }

    private fun launchSettingsIntent(context: Context, primary: Intent, fallback: Intent? = null) {
        primary.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(primary)
            return
        } catch (_: ActivityNotFoundException) {
        }

        val backup = fallback ?: Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
        }
        backup.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(backup)
    }
}
