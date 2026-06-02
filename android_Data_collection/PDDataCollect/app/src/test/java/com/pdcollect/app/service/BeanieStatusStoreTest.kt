package com.pdcollect.app.service

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class BeanieStatusStoreTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        BeanieStatusStore.clear(context)
    }

    @Test
    fun save_roundsUiValuesAndTrimsDeviceName() {
        BeanieStatusStore.save(
            context,
            BeanieStatusSnapshot(
                connected = true,
                status = BeanieService.STATUS_READY,
                deviceName = "  Beanie Alpha  ",
                tskinC = 31.234,
                heatFluxCalPerSec = 1.236,
                batteryPct = 87
            )
        )

        val snapshot = BeanieStatusStore.load(context)

        assertEquals("Beanie Alpha", snapshot?.deviceName)
        assertEquals(31.23, snapshot?.tskinC ?: Double.NaN, 0.0001)
        assertEquals(1.24, snapshot?.heatFluxCalPerSec ?: Double.NaN, 0.0001)
        assertEquals(87, snapshot?.batteryPct)
        assertTrue(snapshot?.connected == true)
    }

    @Test
    fun save_removesBatteryAndNonFiniteValues() {
        BeanieStatusStore.save(
            context,
            BeanieStatusSnapshot(
                connected = false,
                status = BeanieService.STATUS_DISCONNECTED,
                deviceName = "Beanie Beta",
                tskinC = Double.NaN,
                heatFluxCalPerSec = Double.POSITIVE_INFINITY,
                batteryPct = null
            )
        )

        val snapshot = BeanieStatusStore.load(context)

        assertFalse(snapshot?.connected == true)
        assertTrue((snapshot?.tskinC ?: 0.0).isNaN())
        assertTrue((snapshot?.heatFluxCalPerSec ?: 0.0).isNaN())
        assertNull(snapshot?.batteryPct)
    }
}
