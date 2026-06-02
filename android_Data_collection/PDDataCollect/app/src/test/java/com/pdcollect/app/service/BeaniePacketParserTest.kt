package com.pdcollect.app.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BeaniePacketParserTest {

    @Test
    fun parsesTaggedTemperaturePacket() {
        val parser = BeaniePacketParser(BeanieProfile("Test", c1 = 2.0, heatFluxK = 0.01, needsSensorSwap = false))
        val packet = byteArrayOf(
            0xA6.toByte(),
            0x40.toByte(), 0x08.toByte(), // 16.5 * 128 = 2112
            0x80.toByte(), 0x07.toByte()  // 15.0 * 128 = 1920
        )

        val sample = parser.parseTemperaturePacket(packet, 1_000L)

        assertEquals(16.5, sample!!.innerC, 0.001)
        assertEquals(15.0, sample.outerC, 0.001)
        assertEquals(19.5, sample.tskinC, 0.001)
        assertEquals(15.0, sample.heatFluxCalPerSec, 0.001)
    }

    @Test
    fun dropsImpossibleTemperaturePacket() {
        val parser = BeaniePacketParser(BeanieProfile("Test", c1 = 2.0, heatFluxK = 0.01, needsSensorSwap = false))
        val packet = byteArrayOf(
            0xA6.toByte(),
            0x00.toByte(), 0x40.toByte(),
            0x00.toByte(), 0x40.toByte()
        )

        assertNull(parser.parseTemperaturePacket(packet, 1_000L))
    }

    @Test
    fun fallsBackToOppositeSensorOrientationWhenPreferredSwapLooksImpossible() {
        val parser = BeaniePacketParser(BeanieProfile("Test", c1 = 2.0, heatFluxK = 0.01, needsSensorSwap = false))
        val packet = byteArrayOf(
            0xA6.toByte(),
            0x00.toByte(), 0x0E.toByte(), // 28.0 C at /128
            0x00.toByte(), 0x12.toByte()  // 36.0 C at /128
        )

        val sample = parser.parseTemperaturePacket(packet, 1_000L)

        assertEquals(36.0, sample!!.innerC, 0.001)
        assertEquals(28.0, sample.outerC, 0.001)
        assertEquals(52.0, sample.tskinC, 0.001)
        assertEquals(80.0, sample.heatFluxCalPerSec, 0.001)
    }

    @Test
    fun parsesBatteryPercentPacket() {
        val battery = BeaniePacketParser.parseBatteryPercent(
            byteArrayOf(0xA0.toByte(), 0x8A.toByte(), 0x0B.toByte())
        )

        assertEquals(100, battery)
    }

    @Test
    fun parsesImuPacketIntoFifteenSamples() {
        val parser = BeaniePacketParser(BeanieProfile("Test", c1 = 2.0, heatFluxK = 0.01, needsSensorSwap = false))
        val packet = ByteArray(182)
        packet[0] = 0xAA.toByte()
        packet[1] = 0x55.toByte()
        var offset = 2
        repeat(15) { index ->
            fun putShort(value: Short) {
                packet[offset] = (value.toInt() and 0xFF).toByte()
                packet[offset + 1] = ((value.toInt() shr 8) and 0xFF).toByte()
                offset += 2
            }
            putShort((100 + index).toShort())
            putShort((200 + index).toShort())
            putShort((300 + index).toShort())
            putShort((400 + index).toShort())
            putShort((500 + index).toShort())
            putShort((600 + index).toShort())
        }

        val samples = parser.parseImuPacket(packet, 10_000L)

        assertEquals(15, samples.size)
        assertEquals(9_440L, samples.first().timestampMs)
        assertEquals(10_000L, samples.last().timestampMs)
        assertEquals(100.toShort(), samples.first().axRaw)
        assertEquals(600.toShort(), samples.first().gzRaw)
    }

    @Test
    fun parsesStreamImuPacketWithFiveByteHeaderIntoTwentySamples() {
        val parser = BeaniePacketParser(BeanieProfile("Test", c1 = 2.0, heatFluxK = 0.01, needsSensorSwap = false))
        val packet = ByteArray(247)
        packet[0] = 0xAA.toByte()
        packet[1] = 0x55.toByte()
        packet[2] = 0x01.toByte()
        packet[3] = 0xF0.toByte()
        packet[4] = 0x00.toByte()
        var offset = 5
        repeat(20) { index ->
            fun putShort(value: Short) {
                packet[offset] = (value.toInt() and 0xFF).toByte()
                packet[offset + 1] = ((value.toInt() shr 8) and 0xFF).toByte()
                offset += 2
            }
            putShort((1000 + index).toShort())
            putShort((2000 + index).toShort())
            putShort((3000 + index).toShort())
            putShort((4000 + index).toShort())
            putShort((5000 + index).toShort())
            putShort((6000 + index).toShort())
        }

        val samples = parser.parseImuPacket(packet, 20_000L)

        assertEquals(20, samples.size)
        assertEquals(19_240L, samples.first().timestampMs)
        assertEquals(20_000L, samples.last().timestampMs)
        assertEquals(1000.toShort(), samples.first().axRaw)
        assertEquals(6019.toShort(), samples.last().gzRaw)
    }
}
