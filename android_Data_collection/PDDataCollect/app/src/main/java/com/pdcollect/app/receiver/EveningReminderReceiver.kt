package com.pdcollect.app.receiver

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.pdcollect.app.R
import com.pdcollect.app.ui.MainActivity
import com.pdcollect.app.util.Constants
import java.util.Calendar

class EveningReminderReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        showReminderNotification(context)
        scheduleEveningAlarm(context)
    }

    private fun showReminderNotification(context: Context) {
        val tapIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_OPEN_REPORTING, true)
        }
        val pendingIntent = PendingIntent.getActivity(
            context, 0, tapIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(context, Constants.CHANNEL_EVENING)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Evening Check-In")
            .setContentText("Please log your medication and today's physical activity.")
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText("Please log your medication and today's physical activity."))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        try {
            NotificationManagerCompat.from(context)
                .notify(Constants.NOTIFICATION_ID_EVENING_REMINDER, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS permission not granted — skip silently
        }
    }

    companion object {
        private const val ALARM_ID = 104

        fun scheduleEveningAlarm(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                ALARM_ID,
                Intent(context, EveningReminderReceiver::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )

            // Random minute in 20:00–21:59
            val hour = if (Math.random() < 0.5) 20 else 21
            val minute = (0..59).random()

            val target = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            if (target.timeInMillis <= System.currentTimeMillis()) {
                target.add(Calendar.DAY_OF_YEAR, 1)
            }

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && am.canScheduleExactAlarms()) {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, target.timeInMillis, pendingIntent)
                } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, target.timeInMillis, pendingIntent)
                } else {
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, target.timeInMillis, pendingIntent)
                }
            } catch (e: Exception) {
                android.util.Log.e("EveningReminder", "Failed to schedule evening alarm", e)
            }
        }

        fun cancelEveningAlarm(context: Context) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pi = PendingIntent.getBroadcast(
                context,
                ALARM_ID,
                Intent(context, EveningReminderReceiver::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            am.cancel(pi)
            pi.cancel()
        }
    }
}
