package com.pdcollect.app.util

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context

object NotificationHelper {

    fun createChannels(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val sensorChannel = NotificationChannel(
            Constants.CHANNEL_SENSOR,
            "Sensor Collection",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Ongoing notification for sensor data collection"
            setShowBadge(false)
        }

        val tmtChannel = NotificationChannel(
            Constants.CHANNEL_TMT,
            "TMT Reminders",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Reminders to complete Trail Making Test"
        }

        val faceChannel = NotificationChannel(
            Constants.CHANNEL_FACE,
            "Face Distance",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Ongoing notification for face distance measurement"
            setShowBadge(false)
        }

        val hrChannel = NotificationChannel(
            Constants.CHANNEL_HR,
            "Heart Rate Monitor",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Ongoing notification for BLE heart rate recording"
            setShowBadge(false)
        }

        val beanieChannel = NotificationChannel(
            Constants.CHANNEL_BEANIE,
            "Beanie Monitor",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Ongoing notification for Beanie BLE recording"
            setShowBadge(false)
        }

        val eveningChannel = NotificationChannel(
            Constants.CHANNEL_EVENING,
            "Evening Reminders",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Daily reminder to log medications and physical activity"
        }

        manager.createNotificationChannels(
            listOf(sensorChannel, tmtChannel, faceChannel, hrChannel, beanieChannel, eveningChannel)
        )
    }
}
