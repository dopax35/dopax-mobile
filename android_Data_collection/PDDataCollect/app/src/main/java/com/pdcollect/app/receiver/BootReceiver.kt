package com.pdcollect.app.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.service.AntHRService
import com.pdcollect.app.service.BeanieService
import com.pdcollect.app.service.PDCollectService
import com.pdcollect.app.ui.ConsentActivity

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return

        val profile = UserProfile(context)
        if (profile.consentGiven && profile.profileComplete) {
            if (profile.passiveCollectionActive) {
                PDCollectService.start(context)
                // NOTE: FaceDistanceService (type=camera) must NOT be started from the
                // background on Android 14+ (targetSdk 35). Attempting to do so throws a
                // SecurityException because FOREGROUND_SERVICE_CAMERA requires the app to
                // be in a foreground-eligible state (i.e. the user is actively using it).
                // FaceDistanceService is started exclusively from MainActivity.onResume()
                // via syncPassiveServices(), which runs only when the app is foregrounded.
                if (profile.hrDeviceAddress.isNotBlank()) {
                    AntHRService.start(context)
                }
                if (profile.beanieDeviceAddress.isNotBlank()) {
                    BeanieService.start(context)
                }
            }
            BatteryReminderReceiver.scheduleBatteryAlarms(context)
            EveningReminderReceiver.scheduleEveningAlarm(context)
            if (profile.autoUploadEnabled) {
                com.pdcollect.app.worker.DataUploadWorker.scheduleDaily(context)
            }
            com.pdcollect.app.worker.DashboardCacheWorker.schedulePeriodic(context)
            com.pdcollect.app.worker.DashboardCacheWorker.enqueueRefresh(context, initialDelaySeconds = 60)
        } else {
            val launchIntent = Intent(context, ConsentActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(launchIntent)
        }
    }
}
