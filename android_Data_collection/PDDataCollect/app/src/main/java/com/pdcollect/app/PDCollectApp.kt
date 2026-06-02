package com.pdcollect.app

import android.app.Activity
import android.app.Application
import android.os.Bundle
import androidx.work.Configuration
import com.pdcollect.app.util.CrashHandler
import com.pdcollect.app.util.NotificationHelper
import java.util.concurrent.CopyOnWriteArraySet

class PDCollectApp : Application(), Configuration.Provider {
    interface AppForegroundListener {
        fun onAppForegroundChanged(isInForeground: Boolean)
    }

    private val appForegroundListeners = CopyOnWriteArraySet<AppForegroundListener>()
    @Volatile private var resumedActivityCount = 0
    @Volatile private var appInForeground = false

    override fun onCreate() {
        super.onCreate()
        NotificationHelper.createChannels(this)
        Thread.setDefaultUncaughtExceptionHandler(CrashHandler(this))
        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit

            override fun onActivityStarted(activity: Activity) = Unit

            override fun onActivityResumed(activity: Activity) {
                updateAppForegroundState(resumedActivityCount + 1)
            }

            override fun onActivityPaused(activity: Activity) {
                updateAppForegroundState((resumedActivityCount - 1).coerceAtLeast(0))
            }

            override fun onActivityStopped(activity: Activity) = Unit

            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit

            override fun onActivityDestroyed(activity: Activity) = Unit
        })
    }

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setMinimumLoggingLevel(android.util.Log.INFO)
            .build()

    fun isAppInForeground(): Boolean = appInForeground

    fun addAppForegroundListener(listener: AppForegroundListener) {
        appForegroundListeners.add(listener)
    }

    fun removeAppForegroundListener(listener: AppForegroundListener) {
        appForegroundListeners.remove(listener)
    }

    private fun updateAppForegroundState(resumedCount: Int) {
        resumedActivityCount = resumedCount
        val isInForeground = resumedCount > 0
        if (appInForeground == isInForeground) {
            return
        }
        appInForeground = isInForeground
        appForegroundListeners.forEach { it.onAppForegroundChanged(isInForeground) }
    }
}

