package com.pdcollect.app.service

import android.bluetooth.BluetoothGattCharacteristic
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BeanieServiceTest {

    @Test
    fun cccdEnableValueFor_prefersNotificationsWhenSupported() {
        val value = BeanieService.cccdEnableValueFor(
            BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_INDICATE
        )

        assertArrayEquals(byteArrayOf(0x01, 0x00), value)
    }

    @Test
    fun cccdEnableValueFor_usesIndicationsWhenNotificationsUnsupported() {
        val value = BeanieService.cccdEnableValueFor(BluetoothGattCharacteristic.PROPERTY_INDICATE)

        assertArrayEquals(byteArrayOf(0x02, 0x00), value)
    }

    @Test
    fun cccdEnableValueFor_returnsNullWhenCharacteristicCannotPushUpdates() {
        val value = BeanieService.cccdEnableValueFor(BluetoothGattCharacteristic.PROPERTY_READ)

        assertNull(value)
    }

    @Test
    fun supportsRead_detectsReadableCharacteristic() {
        assertTrue(BeanieService.supportsRead(BluetoothGattCharacteristic.PROPERTY_READ))
        assertFalse(BeanieService.supportsRead(BluetoothGattCharacteristic.PROPERTY_NOTIFY))
    }

    @Test
    fun pushModeFor_prefersIndicationsAfterSilentNotifyFallback() {
        val properties = BluetoothGattCharacteristic.PROPERTY_NOTIFY or
            BluetoothGattCharacteristic.PROPERTY_INDICATE

        assertEquals(BeanieService.PushMode.NOTIFY, BeanieService.pushModeFor(properties, false))
        assertEquals(BeanieService.PushMode.INDICATE, BeanieService.pushModeFor(properties, true))
        assertArrayEquals(
            byteArrayOf(0x02, 0x00),
            BeanieService.cccdEnableValueFor(BeanieService.PushMode.INDICATE)
        )
    }

    // ── Regression: live temperature packets must survive the shape filter ──────
    // v3.7.30 replaced byte-scanning with exact per-notification shape matching. These
    // lock in that the real firmware shapes are still accepted, so a future tightening
    // of the filter cannot silently stop temperature/IMU recording again.

    @Test
    fun payloadDecoder_acceptsTaggedTemperaturePacket() {
        // 0xA6 [InLo][InHi][OutLo][OutHi] — inner 24.62C, outer 24.70C at /128 scale
        val inRaw = (24.62 * 128).toInt()
        val outRaw = (24.70 * 128).toInt()
        val packet = byteArrayOf(
            0xA6.toByte(),
            (inRaw and 0xFF).toByte(), ((inRaw shr 8) and 0xFF).toByte(),
            (outRaw and 0xFF).toByte(), ((outRaw shr 8) and 0xFF).toByte()
        )
        val parser = BeaniePacketParser(BeanieRegistry.profileForDevice(""))
        val sample = parser.parseTemperaturePacket(packet, 1_000L)
        assertNotNull("tagged 0xA6 temperature packet must parse", sample)
        // The default profile sets needsSensorSwap=true, so the decoded inner/outer are
        // the transmitted pair swapped. Assert on the set, not on the assignment.
        val decoded = listOf(sample!!.innerC, sample.outerC).sorted()
        assertEquals(24.62, decoded[0], 0.05)
        assertEquals(24.70, decoded[1], 0.05)
    }

    @Test
    fun payloadDecoder_rejectsNvsSentinelAsTemperature() {
        // Garbage/sentinel frame that previously produced the bogus 87.62C rows.
        val parser = BeaniePacketParser(BeanieRegistry.profileForDevice(""))
        val allZero = parser.parseTemperaturePacket(byteArrayOf(0, 0, 0, 0), 1_000L)
        assertNull("all-zero legacy frame must not be accepted as a reading", allZero)
    }
}
