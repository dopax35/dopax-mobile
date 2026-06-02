package com.pdcollect.app.service

import android.bluetooth.BluetoothGattCharacteristic
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
}
