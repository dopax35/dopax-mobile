package com.pdcollect.app.service

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BeanieDiscoveryTest {

    @Test
    fun detectsLikelyBeanieNames() {
        assertTrue(BeanieDiscovery.isLikelyBeanieName("Beanie V3"))
        assertTrue(BeanieDiscovery.isLikelyBeanieName("NRF52 Device"))
        assertTrue(BeanieDiscovery.isLikelyBeanieName("my-v3-hat"))
        assertTrue(BeanieDiscovery.isLikelyBeanieName("v4e"))
    }

    @Test
    fun rejectsUnrelatedNames() {
        assertFalse(BeanieDiscovery.isLikelyBeanieName("Polar H10"))
        assertFalse(BeanieDiscovery.isLikelyBeanieName("Pixel 8"))
        assertFalse(BeanieDiscovery.isLikelyBeanieName("Unknown"))
    }

    @Test
    fun matchesSavedDeviceIdentity_acceptsSavedAddressEvenWithoutBeanieAdvertisement() {
        assertTrue(
            BeanieDiscovery.matchesSavedDeviceIdentity(
                address = "AA:BB:CC:DD:EE:FF",
                scannedName = "Unknown",
                advertisesBeanieService = false,
                savedAddress = "aa:bb:cc:dd:ee:ff",
                savedName = ""
            )
        )
    }

    @Test
    fun matchesSavedDeviceIdentity_acceptsSavedNameEvenWithoutServiceUuid() {
        assertTrue(
            BeanieDiscovery.matchesSavedDeviceIdentity(
                address = "11:22:33:44:55:66",
                scannedName = "v4e_Ori's Beanie",
                advertisesBeanieService = false,
                savedAddress = "",
                savedName = "v4e_Ori's Beanie"
            )
        )
    }

    @Test
    fun matchesSavedDeviceIdentity_acceptsFirmwarePrefixNameVariants() {
        assertTrue(
            BeanieDiscovery.matchesSavedDeviceIdentity(
                address = "11:22:33:44:55:66",
                scannedName = "Ori's Beanie",
                advertisesBeanieService = false,
                savedAddress = "",
                savedName = "v4e_Ori's Beanie"
            )
        )

        assertTrue(
            BeanieDiscovery.matchesSavedDeviceIdentity(
                address = "11:22:33:44:55:66",
                scannedName = "v4e_Black_08",
                advertisesBeanieService = false,
                savedAddress = "",
                savedName = "Black 08"
            )
        )
    }
}
