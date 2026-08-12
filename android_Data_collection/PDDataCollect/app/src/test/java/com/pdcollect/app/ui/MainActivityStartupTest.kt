package com.pdcollect.app.ui

import android.content.Context
import android.view.View
import androidx.test.core.app.ApplicationProvider
import com.pdcollect.app.R
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.service.BeanieStatusSnapshot
import com.pdcollect.app.service.BeanieStatusStore
import com.pdcollect.app.util.Constants
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MainActivityStartupTest {

    private lateinit var context: Context
    private lateinit var profile: UserProfile

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        profile = UserProfile(context)
        profile.clearAll()
        profile.consentGiven = true
        profile.profileComplete = true
        // A finished profile means finished onboarding v2 as well; without the
        // session window MainActivity bounces straight back to ProfileSetup.
        profile.onboardingVersion = 2
        profile.testTimeCustom = "14:00"
        profile.userId = "TEST01"
        profile.passiveCollectionActive = false
        profile.keyloggingEnabled = false
        profile.faceDistanceMode = Constants.FACE_DISTANCE_MODE_OFF
    }

    @After
    fun tearDown() {
        profile.clearAll()
        File(context.getExternalFilesDir(null), Constants.BASE_DIR).deleteRecursively()
        context.cacheDir.listFiles()
            ?.filter { it.name.startsWith("PDCollect_") }
            ?.forEach { it.delete() }
        context.filesDir.listFiles()
            ?.filter { it.name.contains(Constants.GRAPH_CACHE_FILE) }
            ?.forEach { it.delete() }
    }

    @Test
    fun completedProfile_launchesMainActivityWithoutCrash() {
        val controller = Robolectric.buildActivity(MainActivity::class.java).setup()
        val activity = controller.get()
        try {
            assertNotNull(activity.findViewById<View>(R.id.topAppBar))
            assertNotNull(activity.findViewById<View>(R.id.chartDailyStrideLength))
            val titleField = Class.forName("com.pdcollect.app.ui.view.DailyMetricChartView")
                .getDeclaredField("title")
                .apply { isAccessible = true }
            val chart = activity.findViewById<View>(R.id.chartDailyStrideLength)
            assertEquals("Stride Length", titleField.get(chart))
        } finally {
            controller.pause().stop().destroy()
        }
    }

    @Test
    fun staleConnectedBeanieSnapshotDoesNotKeepHomeCardVisible() {
        BeanieStatusStore.save(
            context,
            BeanieStatusSnapshot(
                connected = true,
                status = "READY",
                deviceName = "Beanie Alpha",
                tskinC = Double.NaN,
                heatFluxCalPerSec = Double.NaN,
                batteryPct = null
            )
        )

        val controller = Robolectric.buildActivity(MainActivity::class.java).setup()
        val activity = controller.get()
        try {
            assertEquals(View.GONE, activity.findViewById<View>(R.id.cardBeanieVitals).visibility)
        } finally {
            controller.pause().stop().destroy()
        }
    }

    @Test
    fun beanieVitalsRemainVisibleDuringReconnectWhenLastReadingExists() {
        val controller = Robolectric.buildActivity(MainActivity::class.java).setup()
        val activity = controller.get()
        try {
            val render = MainActivity::class.java.getDeclaredMethod(
                "renderBeanieVitals",
                Boolean::class.javaPrimitiveType,
                Double::class.javaPrimitiveType,
                Double::class.javaPrimitiveType,
                Boolean::class.javaPrimitiveType,
                String::class.java,
                java.lang.Double::class.java
            ).apply { isAccessible = true }

            render.invoke(activity, false, 26.24, 1.63, true, null, null)

            assertEquals(View.VISIBLE, activity.findViewById<View>(R.id.cardBeanieVitals).visibility)
        } finally {
            controller.pause().stop().destroy()
        }
    }
}
