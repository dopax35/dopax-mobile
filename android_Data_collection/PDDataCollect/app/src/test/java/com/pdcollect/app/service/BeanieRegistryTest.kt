package com.pdcollect.app.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BeanieRegistryTest {

    @Test
    fun profileForDevice_matchesFirmwarePrefixedBeanieName() {
        val profile = BeanieRegistry.profileForDevice("v4e_Ori's Beanie")

        assertEquals("Ori's Beanie", profile.name)
        assertFalse(profile.needsSensorSwap)
        assertEquals(2.7, profile.c1, 0.0001)
    }

    @Test
    fun profileForDevice_fallsBackToDefaultForUnknownDevice() {
        val profile = BeanieRegistry.profileForDevice("mystery-device")

        assertEquals("Default", profile.name)
        assertTrue(profile.needsSensorSwap)
    }
}
