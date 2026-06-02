package com.pdcollect.app.receiver

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.pdcollect.app.R
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.ui.TestBatteryCoordinatorActivity
import com.pdcollect.app.util.Constants
import java.util.Calendar

class BatteryReminderReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val channel = NotificationChannel("battery_reminders", "Daily Test Reminders", NotificationManager.IMPORTANCE_HIGH)
        notificationManager.createNotificationChannel(channel)

        val activityIntent = Intent(context, TestBatteryCoordinatorActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            context, 0, activityIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val title = "DopaX Assessment Time"
        val text = "It's time to run your complete test battery. Please tap here to start."

        val notification = NotificationCompat.Builder(context, "battery_reminders")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        android.util.Log.d("BatteryReminders", "onReceive: Firing test prompt at ${System.currentTimeMillis()}")
        notificationManager.notify(Constants.NOTIFICATION_ID_BATTERY_REMINDER, notification)
        
        // Schedule next day's alarms instantly so it seamlessly repeats!
        scheduleBatteryAlarms(context)
    }

    private fun getAssessmentText(): String {
        return "It's time for your daily assessments. Tap to begin."
    }

    companion object {
        private const val ALARM_MORNING_ID = 101
        private const val ALARM_NOON_ID = 102
        private const val ALARM_RANDOM_ID = 103

        fun scheduleBatteryAlarms(context: Context) {
            val profile = UserProfile(context)
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            val intentMorning = Intent(context, BatteryReminderReceiver::class.java).let {
                PendingIntent.getBroadcast(context, ALARM_MORNING_ID, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            }
            val intentNoon = Intent(context, BatteryReminderReceiver::class.java).let {
                PendingIntent.getBroadcast(context, ALARM_NOON_ID, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            }
            val intentRandom = Intent(context, BatteryReminderReceiver::class.java).let {
                PendingIntent.getBroadcast(context, ALARM_RANDOM_ID, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            }

            // Morning
            val mParts = profile.testTimeMorning.split(":")
            var targetMorning = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, mParts.getOrNull(0)?.toIntOrNull() ?: 8)
                set(Calendar.MINUTE, mParts.getOrNull(1)?.toIntOrNull() ?: 0)
                set(Calendar.SECOND, 0)
            }
            if (targetMorning.timeInMillis <= System.currentTimeMillis()) {
                targetMorning.add(Calendar.DAY_OF_YEAR, 1)
            }

            // Noon
            val nParts = profile.testTimeNoon.split(":")
            var targetNoon = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, nParts.getOrNull(0)?.toIntOrNull() ?: 12)
                set(Calendar.MINUTE, nParts.getOrNull(1)?.toIntOrNull() ?: 0)
                set(Calendar.SECOND, 0)
            }
            if (targetNoon.timeInMillis <= System.currentTimeMillis()) {
                targetNoon.add(Calendar.DAY_OF_YEAR, 1)
            }

            // Random (Between 15:00 and 20:00)
            var targetRandom = Calendar.getInstance().apply {
                val hour = (15..20).random()
                val minute = (0..59).random()
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                profile.testTimeRandom = String.format(java.util.Locale.US, "%02d:%02d", hour, minute)
            }
            if (targetRandom.timeInMillis <= System.currentTimeMillis()) {
                targetRandom.add(Calendar.DAY_OF_YEAR, 1)
            }

            // Try scheduling exact if permission granted, otherwise fallback to standard
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    if (am.canScheduleExactAlarms()) {
                        android.util.Log.d("BatteryReminders", "Scheduling EXACT: Morning=${targetMorning.timeInMillis}, Noon=${targetNoon.timeInMillis}, Random=${targetRandom.timeInMillis}")
                        am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, targetMorning.timeInMillis, intentMorning)
                        am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, targetNoon.timeInMillis, intentNoon)
                        am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, targetRandom.timeInMillis, intentRandom)
                    } else {
                        android.util.Log.w("BatteryReminders", "EXACT ALARM PERMISSION MISSING! Fallback to non-exact.")
                        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, targetMorning.timeInMillis, intentMorning)
                        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, targetNoon.timeInMillis, intentNoon)
                        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, targetRandom.timeInMillis, intentRandom)
                    }
                } else {
                    // minSdk 29+ ensures M (setExactAndAllowWhileIdle) availability
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, targetMorning.timeInMillis, intentMorning)
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, targetNoon.timeInMillis, intentNoon)
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, targetRandom.timeInMillis, intentRandom)
                }
            } catch (e: Exception) {
                android.util.Log.e("BatteryReminders", "Scheduling failure", e)
            }
        }

        /**
         * Cancel all three test-prompt alarms. Used by the Withdraw flow so that
         * a withdrawn participant doesn't keep receiving daily reminders. Mirrors
         * the PendingIntent construction in [scheduleBatteryAlarms] exactly so
         * AlarmManager finds the same intents.
         */
        fun cancelBatteryAlarms(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            for (id in intArrayOf(ALARM_MORNING_ID, ALARM_NOON_ID, ALARM_RANDOM_ID)) {
                val pi = PendingIntent.getBroadcast(
                    context,
                    id,
                    Intent(context, BatteryReminderReceiver::class.java),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                am.cancel(pi)
                pi.cancel()
            }
            android.util.Log.d("BatteryReminders", "Cancelled all battery alarms")
        }
    }
}
