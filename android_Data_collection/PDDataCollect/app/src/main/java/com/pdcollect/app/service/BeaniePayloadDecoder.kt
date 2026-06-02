package com.pdcollect.app.service

sealed class BeaniePayloadFrame(val bytes: ByteArray) {
    class Battery(bytes: ByteArray) : BeaniePayloadFrame(bytes)
    class Temperature(bytes: ByteArray) : BeaniePayloadFrame(bytes)
    class Imu(bytes: ByteArray) : BeaniePayloadFrame(bytes)
}

object BeaniePayloadDecoder {
    private const val BATTERY_TAG = 0xA0
    private const val TEMPERATURE_TAG = 0xA6
    private const val IMU_TAG_0 = 0xAA
    private const val IMU_TAG_1 = 0x55
    private const val BATTERY_PACKET_SIZE = 3
    private const val TAGGED_TEMPERATURE_PACKET_SIZE = 5
    private const val LEGACY_TEMPERATURE_PACKET_SIZE = 4
    private const val LEGACY_IMU_PACKET_SIZE = 182
    private const val STREAM_IMU_HEADER_SIZE = 5
    private const val STREAM_IMU_FULL_PACKET_SIZE = 247
    private const val STREAM_IMU_SAMPLE_BYTES = 12
    private const val STREAM_IMU_TYPE = 0x01
    private const val STREAM_IMU_PAYLOAD_BYTES = 0x00F0
    private const val MAX_STREAM_BUFFER_BYTES = 4096

    fun split(data: ByteArray): List<BeaniePayloadFrame> {
        if (data.isEmpty()) return emptyList()
        if (data.size == LEGACY_TEMPERATURE_PACKET_SIZE) {
            return listOf(BeaniePayloadFrame.Temperature(data.copyOf()))
        }

        val frames = mutableListOf<BeaniePayloadFrame>()
        var offset = 0
        while (offset < data.size) {
            val b0 = data[offset].toInt() and 0xFF
            when {
                b0 == BATTERY_TAG -> {
                    if (offset + BATTERY_PACKET_SIZE > data.size) break
                    frames += BeaniePayloadFrame.Battery(
                        data.copyOfRange(offset, offset + BATTERY_PACKET_SIZE)
                    )
                    offset += BATTERY_PACKET_SIZE
                }

                b0 == TEMPERATURE_TAG -> {
                    if (offset + TAGGED_TEMPERATURE_PACKET_SIZE > data.size) break
                    frames += BeaniePayloadFrame.Temperature(
                        data.copyOfRange(offset, offset + TAGGED_TEMPERATURE_PACKET_SIZE)
                    )
                    offset += TAGGED_TEMPERATURE_PACKET_SIZE
                }

                b0 == IMU_TAG_0 &&
                    offset + 1 < data.size &&
                    (data[offset + 1].toInt() and 0xFF) == IMU_TAG_1 -> {
                    val frameSize = imuFrameSize(data, offset)
                    if (frameSize == null) {
                        offset++
                        continue
                    }
                    frames += BeaniePayloadFrame.Imu(data.copyOfRange(offset, offset + frameSize))
                    offset += frameSize
                }

                offset + LEGACY_TEMPERATURE_PACKET_SIZE == data.size &&
                    looksLikeLegacyTemperaturePacket(data, offset) -> {
                    frames += BeaniePayloadFrame.Temperature(
                        data.copyOfRange(offset, offset + LEGACY_TEMPERATURE_PACKET_SIZE)
                    )
                    offset += LEGACY_TEMPERATURE_PACKET_SIZE
                }

                else -> offset++
            }
        }

        return frames
    }

    fun splitStream(buffer: ArrayDeque<Byte>, data: ByteArray): List<BeaniePayloadFrame> {
        data.forEach { buffer.addLast(it) }
        while (buffer.size > MAX_STREAM_BUFFER_BYTES) buffer.removeFirst()

        val frames = mutableListOf<BeaniePayloadFrame>()
        while (buffer.isNotEmpty()) {
            val b0 = buffer[0].toInt() and 0xFF
            when {
                b0 == BATTERY_TAG -> {
                    if (buffer.size < BATTERY_PACKET_SIZE) break
                    frames += BeaniePayloadFrame.Battery(buffer.removeBytes(BATTERY_PACKET_SIZE))
                }

                b0 == TEMPERATURE_TAG -> {
                    if (buffer.size < TAGGED_TEMPERATURE_PACKET_SIZE) break
                    frames += BeaniePayloadFrame.Temperature(buffer.removeBytes(TAGGED_TEMPERATURE_PACKET_SIZE))
                }

                b0 == IMU_TAG_0 -> {
                    if (buffer.size < 2) break
                    val b1 = buffer[1].toInt() and 0xFF
                    if (b1 != IMU_TAG_1) {
                        buffer.removeFirst()
                        continue
                    }

                    val frameSize = bufferedImuFrameSize(buffer)
                    if (frameSize == null) {
                        if (buffer.size < STREAM_IMU_HEADER_SIZE) break
                        buffer.removeFirst()
                        continue
                    }
                    if (buffer.size < frameSize) break
                    frames += BeaniePayloadFrame.Imu(buffer.removeBytes(frameSize))
                }

                else -> {
                    if (buffer.size == LEGACY_TEMPERATURE_PACKET_SIZE &&
                        looksLikeBufferedLegacyTemperaturePacket(buffer)
                    ) {
                        frames += BeaniePayloadFrame.Temperature(buffer.removeBytes(LEGACY_TEMPERATURE_PACKET_SIZE))
                    } else {
                        buffer.removeFirst()
                    }
                }
            }
        }

        return frames
    }

    private fun imuFrameSize(data: ByteArray, offset: Int): Int? {
        if (offset + 1 >= data.size) return null
        if ((data[offset + 1].toInt() and 0xFF) != IMU_TAG_1) return null

        val remaining = data.size - offset
        if (remaining >= STREAM_IMU_HEADER_SIZE &&
            (data[offset + 2].toInt() and 0xFF) == STREAM_IMU_TYPE
        ) {
            val payloadBytes = (data[offset + 3].toInt() and 0xFF) or
                ((data[offset + 4].toInt() and 0xFF) shl 8)
            if (payloadBytes == STREAM_IMU_PAYLOAD_BYTES) {
                if (remaining >= STREAM_IMU_FULL_PACKET_SIZE) return STREAM_IMU_FULL_PACKET_SIZE
                val sampleBytes = ((remaining - STREAM_IMU_HEADER_SIZE) / STREAM_IMU_SAMPLE_BYTES) *
                    STREAM_IMU_SAMPLE_BYTES
                val partialSize = STREAM_IMU_HEADER_SIZE + sampleBytes
                return partialSize.takeIf { it >= STREAM_IMU_HEADER_SIZE + STREAM_IMU_SAMPLE_BYTES }
            }
        }

        return LEGACY_IMU_PACKET_SIZE.takeIf { remaining >= it }
    }

    private fun bufferedImuFrameSize(buffer: ArrayDeque<Byte>): Int? {
        if (buffer.size < 2) return null
        if ((buffer[1].toInt() and 0xFF) != IMU_TAG_1) return null

        if (buffer.size >= STREAM_IMU_HEADER_SIZE &&
            (buffer[2].toInt() and 0xFF) == STREAM_IMU_TYPE
        ) {
            val payloadBytes = (buffer[3].toInt() and 0xFF) or
                ((buffer[4].toInt() and 0xFF) shl 8)
            if (payloadBytes == STREAM_IMU_PAYLOAD_BYTES) return STREAM_IMU_FULL_PACKET_SIZE
        }

        return LEGACY_IMU_PACKET_SIZE
    }

    private fun ArrayDeque<Byte>.removeBytes(count: Int): ByteArray {
        return ByteArray(count) { removeFirst() }
    }

    private fun looksLikeBufferedLegacyTemperaturePacket(buffer: ArrayDeque<Byte>): Boolean {
        if (buffer.size != LEGACY_TEMPERATURE_PACKET_SIZE) return false
        val data = ByteArray(LEGACY_TEMPERATURE_PACKET_SIZE) { index -> buffer[index] }
        return looksLikeLegacyTemperaturePacket(data, 0)
    }

    private fun looksLikeLegacyTemperaturePacket(data: ByteArray, offset: Int): Boolean {
        if (offset + LEGACY_TEMPERATURE_PACKET_SIZE > data.size) return false
        val rawIn = (data[offset].toInt() and 0xFF) or ((data[offset + 1].toInt() and 0xFF) shl 8)
        val rawOut = (data[offset + 2].toInt() and 0xFF) or ((data[offset + 3].toInt() and 0xFF) shl 8)
        if (rawIn == 0 && rawOut == 0) return false
        return looksPlausibleTemperaturePair(rawIn / 128.0, rawOut / 128.0) ||
            looksPlausibleTemperaturePair(rawIn / 16.0, rawOut / 16.0)
    }

    private fun looksPlausibleTemperaturePair(inner: Double, outer: Double): Boolean {
        return inner.isFinite() &&
            outer.isFinite() &&
            inner in -20.0..80.0 &&
            outer in -20.0..80.0 &&
            !(kotlin.math.abs(inner) < 0.5 && kotlin.math.abs(outer) < 0.5)
    }
}
