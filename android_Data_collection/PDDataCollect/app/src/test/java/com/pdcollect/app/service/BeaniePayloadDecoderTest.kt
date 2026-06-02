package com.pdcollect.app.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BeaniePayloadDecoderTest {

    @Test
    fun split_detectsTaggedTemperaturePacket() {
        val frames = BeaniePayloadDecoder.split(
            byteArrayOf(
                0xA6.toByte(),
                0x40.toByte(), 0x08.toByte(),
                0x80.toByte(), 0x07.toByte()
            )
        )

        assertEquals(1, frames.size)
        assertTrue(frames.first() is BeaniePayloadFrame.Temperature)
    }

    @Test
    fun split_detectsBatchedBatteryAndTemperaturePackets() {
        val frames = BeaniePayloadDecoder.split(
            byteArrayOf(
                0xA0.toByte(), 0x8A.toByte(), 0x0B.toByte(),
                0xA6.toByte(), 0x40.toByte(), 0x08.toByte(), 0x80.toByte(), 0x07.toByte()
            )
        )

        assertEquals(2, frames.size)
        assertTrue(frames[0] is BeaniePayloadFrame.Battery)
        assertTrue(frames[1] is BeaniePayloadFrame.Temperature)
    }

    @Test
    fun split_detectsLegacyFourByteTemperaturePacket() {
        val frames = BeaniePayloadDecoder.split(
            byteArrayOf(0x40.toByte(), 0x08.toByte(), 0x80.toByte(), 0x07.toByte())
        )

        assertEquals(1, frames.size)
        assertTrue(frames.first() is BeaniePayloadFrame.Temperature)
    }

    @Test
    fun split_detectsLegacyFourByteTemperaturePacketAfterBatteryPacket() {
        val frames = BeaniePayloadDecoder.split(
            byteArrayOf(
                0xA0.toByte(), 0x8A.toByte(), 0x0B.toByte(),
                0x40.toByte(), 0x08.toByte(), 0x80.toByte(), 0x07.toByte()
            )
        )

        assertEquals(2, frames.size)
        assertTrue(frames[0] is BeaniePayloadFrame.Battery)
        assertTrue(frames[1] is BeaniePayloadFrame.Temperature)
    }

    @Test
    fun splitStream_detectsLegacyFourByteTemperaturePacket() {
        val buffer = ArrayDeque<Byte>()

        val frames = BeaniePayloadDecoder.splitStream(
            buffer,
            byteArrayOf(0x40.toByte(), 0x08.toByte(), 0x80.toByte(), 0x07.toByte())
        )

        assertEquals(1, frames.size)
        assertTrue(frames.first() is BeaniePayloadFrame.Temperature)
        assertTrue(buffer.isEmpty())
    }

    @Test
    fun splitStream_detectsLegacyFourByteTemperaturePacketAfterBatteryPacket() {
        val buffer = ArrayDeque<Byte>()

        val frames = BeaniePayloadDecoder.splitStream(
            buffer,
            byteArrayOf(
                0xA0.toByte(), 0x8A.toByte(), 0x0B.toByte(),
                0x40.toByte(), 0x08.toByte(), 0x80.toByte(), 0x07.toByte()
            )
        )

        assertEquals(2, frames.size)
        assertTrue(frames[0] is BeaniePayloadFrame.Battery)
        assertTrue(frames[1] is BeaniePayloadFrame.Temperature)
        assertTrue(buffer.isEmpty())
    }

    @Test
    fun split_detectsStreamImuPacketWithHeader() {
        val packet = ByteArray(247)
        packet[0] = 0xAA.toByte()
        packet[1] = 0x55.toByte()
        packet[2] = 0x01.toByte()
        packet[3] = 0xF0.toByte()
        packet[4] = 0x00.toByte()
        packet[5] = 0x34.toByte()
        packet[6] = 0x12.toByte()

        val frames = BeaniePayloadDecoder.split(packet)

        assertEquals(1, frames.size)
        assertTrue(frames.first() is BeaniePayloadFrame.Imu)
        assertEquals(247, frames.first().bytes.size)
    }

    @Test
    fun splitStream_reassemblesMisalignedStreamImuPacketAcrossNotifications() {
        val packet = ByteArray(247)
        packet[0] = 0xAA.toByte()
        packet[1] = 0x55.toByte()
        packet[2] = 0x01.toByte()
        packet[3] = 0xF0.toByte()
        packet[4] = 0x00.toByte()
        packet[5] = 0x34.toByte()
        packet[6] = 0x12.toByte()
        val firstNotification = ByteArray(180) { 0x7F.toByte() } + packet.copyOfRange(0, 67)
        val secondNotification = packet.copyOfRange(67, packet.size)
        val buffer = ArrayDeque<Byte>()

        val firstFrames = BeaniePayloadDecoder.splitStream(buffer, firstNotification)
        val secondFrames = BeaniePayloadDecoder.splitStream(buffer, secondNotification)

        assertTrue(firstFrames.isEmpty())
        assertEquals(1, secondFrames.size)
        assertTrue(secondFrames.first() is BeaniePayloadFrame.Imu)
        assertEquals(247, secondFrames.first().bytes.size)
    }

    @Test
    fun splitStream_reassemblesStreamImuPacketWhenFinalNotificationIsFourBytes() {
        val packet = ByteArray(247)
        packet[0] = 0xAA.toByte()
        packet[1] = 0x55.toByte()
        packet[2] = 0x01.toByte()
        packet[3] = 0xF0.toByte()
        packet[4] = 0x00.toByte()
        packet[243] = 0x40.toByte()
        packet[244] = 0x08.toByte()
        packet[245] = 0x80.toByte()
        packet[246] = 0x07.toByte()
        val buffer = ArrayDeque<Byte>()

        val firstFrames = BeaniePayloadDecoder.splitStream(buffer, packet.copyOfRange(0, 243))
        val secondFrames = BeaniePayloadDecoder.splitStream(buffer, packet.copyOfRange(243, 247))

        assertTrue(firstFrames.isEmpty())
        assertEquals(1, secondFrames.size)
        assertTrue(secondFrames.first() is BeaniePayloadFrame.Imu)
        assertEquals(247, secondFrames.first().bytes.size)
        assertTrue(buffer.isEmpty())
    }

    @Test
    fun split_doesNotInventLegacyTemperatureInsideLargeStreamChunk() {
        val packet = ByteArray(247)
        packet[0] = 0x01.toByte()
        packet[1] = 0x02.toByte()
        packet[120] = 0x40.toByte()
        packet[121] = 0x08.toByte()
        packet[122] = 0x80.toByte()
        packet[123] = 0x07.toByte()

        val frames = BeaniePayloadDecoder.split(packet)

        assertTrue(frames.none { it is BeaniePayloadFrame.Temperature })
    }
}
