package com.pdcollect.app.service

import kotlin.math.abs
import kotlin.math.round
import kotlin.math.sqrt

class BeaniePacketParser(
    private val profile: BeanieProfile
) {

    data class TemperatureSample(
        val timestampMs: Long,
        val innerC: Double,
        val outerC: Double,
        val tskinC: Double,
        val heatFluxCalPerSec: Double
    )

    data class ImuSample(
        val timestampMs: Long,
        val axRaw: Short,
        val ayRaw: Short,
        val azRaw: Short,
        val gxRaw: Short,
        val gyRaw: Short,
        val gzRaw: Short,
        val axG: Double,
        val ayG: Double,
        val azG: Double,
        val accelMagG: Double,
        val gxDps: Double,
        val gyDps: Double,
        val gzDps: Double,
        val gyroMagDps: Double
    )

    private var lastGuardedInner: Double? = null
    private var lastGuardedOuter: Double? = null

    fun parseTemperaturePacket(data: ByteArray, timestampMs: Long): TemperatureSample? {
        if (data.size == 5 && (data[0].toInt() and 0xFF) == 0xA6) {
            val rawInU = (data[1].toInt() and 0xFF) or ((data[2].toInt() and 0xFF) shl 8)
            val rawOutU = (data[3].toInt() and 0xFF) or ((data[4].toInt() and 0xFF) shl 8)
            return parseTemperatureWords(rawInU, rawOutU, timestampMs)
        }
        if (data.size == 4) {
            val rawInU = (data[0].toInt() and 0xFF) or ((data[1].toInt() and 0xFF) shl 8)
            val rawOutU = (data[2].toInt() and 0xFF) or ((data[3].toInt() and 0xFF) shl 8)
            return parseTemperatureWords(rawInU, rawOutU, timestampMs)
        }
        return null
    }

    private fun parseTemperatureWords(rawInU: Int, rawOutU: Int, timestampMs: Long): TemperatureSample? {
        val scaledCandidates = mutableListOf(
            rawInU.toShort().toInt() / 128.0 to rawOutU.toShort().toInt() / 128.0
        )
        if (shouldTryLegacyScale(scaledCandidates.first().first, scaledCandidates.first().second, rawInU, rawOutU)) {
            scaledCandidates += rawInU.toShort().toInt() / 16.0 to rawOutU.toShort().toInt() / 16.0
        }

        val swapCandidates = listOf(profile.needsSensorSwap, !profile.needsSensorSwap).distinct()
        for ((inC, outC) in scaledCandidates) {
            for (needsSensorSwap in swapCandidates) {
                parseDecodedTemperatures(inC, outC, timestampMs, needsSensorSwap)?.let { return it }
            }
        }
        return null
    }

    private fun shouldTryLegacyScale(inC: Double, outC: Double, rawInU: Int, rawOutU: Int): Boolean {
        val hasSufficientSignal = rawInU > 100 || rawOutU > 100
        val primaryLooksWrong = inC < 5.0 || outC < 5.0 || inC > 80.0 || outC > 80.0
        return hasSufficientSignal && primaryLooksWrong
    }

    private fun parseDecodedTemperatures(
        inC: Double,
        outC: Double,
        timestampMs: Long,
        needsSensorSwap: Boolean
    ): TemperatureSample? {
        val (innerRaw, outerRaw) = if (needsSensorSwap) outC to inC else inC to outC

        // Sanity gate, reference parity (BLEReader.swift parseTempV2 / BleViewModel):
        //   "Drop physically impossible values: garbage ADC, NVS sentinel
        //    (rawIn=rawOut~=0), out-of-range, or sensor not-ready glitches."
        // The near-zero sentinel check was missing here. `processIncoming` routes any
        // 4-byte notification straight to this parser, bypassing
        // BeaniePayloadDecoder.looksLikeLegacyTemperaturePacket (which does reject
        // rawIn==0 && rawOut==0), so an all-zero frame was being recorded as a real
        // 0.00C / 0.00C reading. Caught by BeanieServiceTest.
        if (innerRaw <= -5.0 || innerRaw >= 60.0 ||
            outerRaw <= -15.0 || outerRaw >= 60.0 ||
            (abs(innerRaw) < 0.05 && abs(outerRaw) < 0.05)
        ) {
            return null
        }

        var guardedInner = innerRaw
        var guardedOuter = outerRaw
        val lastInner = lastGuardedInner
        val lastOuter = lastGuardedOuter
        if (lastInner != null && lastOuter != null) {
            val deltaInner = abs(innerRaw - lastInner)
            val deltaOuter = abs(outerRaw - lastOuter)
            when {
                deltaInner > 5.0 && deltaOuter > 5.0 -> {
                    guardedInner = lastInner
                    guardedOuter = lastOuter
                }
                deltaInner > 3.0 && deltaOuter < 0.2 -> guardedInner = lastInner
                deltaOuter > 3.0 && deltaInner < 0.2 -> guardedOuter = lastOuter
                innerRaw > 20.0 && outerRaw > 15.0 && (innerRaw - outerRaw) < -5.0 -> {
                    guardedInner = lastInner
                    guardedOuter = lastOuter
                }
            }
        } else if (innerRaw > 25.0 && outerRaw > 25.0 && (innerRaw - outerRaw) < -5.0) {
            return null
        }

        lastGuardedInner = guardedInner
        lastGuardedOuter = guardedOuter

        val innerC = round2(guardedInner)
        val outerC = round2(guardedOuter)
        val deltaT = innerC - outerC
        val tskinC = round2(innerC + profile.c1 * deltaT)
        val heatFlux = round2(profile.heatFluxK * deltaT * 1000.0)

        return TemperatureSample(timestampMs, innerC, outerC, tskinC, heatFlux)
    }

    fun parseImuPacket(data: ByteArray, baseTimestampMs: Long): List<ImuSample> {
        if (data.size < 14) return emptyList()
        if ((data[0].toInt() and 0xFF) != 0xAA || (data[1].toInt() and 0xFF) != 0x55) return emptyList()

        val isStreamPacket = data.size >= 5 &&
            (data[2].toInt() and 0xFF) == 0x01 &&
            (((data[3].toInt() and 0xFF) or ((data[4].toInt() and 0xFF) shl 8)) == 0x00F0)
        val sampleOffset = if (isStreamPacket) 5 else 2
        val maxSamples = if (isStreamPacket) 20 else 15
        val sampleCount = minOf(maxSamples, (data.size - sampleOffset) / 12)
        if (sampleCount <= 0) return emptyList()

        val samples = mutableListOf<ImuSample>()
        var offset = sampleOffset
        repeat(sampleCount) { index ->
            fun toI16(idx: Int): Short =
                ((data[idx].toInt() and 0xFF) or ((data[idx + 1].toInt() and 0xFF) shl 8)).toShort()

            val ax = toI16(offset)
            val ay = toI16(offset + 2)
            val az = toI16(offset + 4)
            val gx = toI16(offset + 6)
            val gy = toI16(offset + 8)
            val gz = toI16(offset + 10)
            offset += 12

            val allEqual = ax == ay && ay == az && az == gx && gx == gy && gy == gz
            if (allEqual) return@repeat

            val axG = ax / 4096.0
            val ayG = ay / 4096.0
            val azG = az / 4096.0
            val gxDps = gx / 16.384
            val gyDps = gy / 16.384
            val gzDps = gz / 16.384
            val timestampMs = baseTimestampMs - ((sampleCount - 1 - index) * 40L)

            samples.add(
                ImuSample(
                    timestampMs = timestampMs,
                    axRaw = ax,
                    ayRaw = ay,
                    azRaw = az,
                    gxRaw = gx,
                    gyRaw = gy,
                    gzRaw = gz,
                    axG = axG,
                    ayG = ayG,
                    azG = azG,
                    accelMagG = sqrt(axG * axG + ayG * ayG + azG * azG),
                    gxDps = gxDps,
                    gyDps = gyDps,
                    gzDps = gzDps,
                    gyroMagDps = sqrt(gxDps * gxDps + gyDps * gyDps + gzDps * gzDps)
                )
            )
        }
        return samples
    }

    companion object {
        fun parseBatteryPercent(data: ByteArray): Int? {
            if (data.size < 3 || (data[0].toInt() and 0xFF) != 0xA0) return null

            val ain = ((data[1].toInt() and 0xFF) or ((data[2].toInt() and 0xFF) shl 8)).toDouble()
            val pctBase = when {
                ain > 2954 -> 100.0
                ain > 2758 -> 0.0019681649 * ain * ain - 10.813688 * ain + 14871.0
                else -> 0.0566 * ain - 138.41
            }
            val pctSmall = 1.7248 * pctBase - 72.476
            return pctSmall.toInt().coerceIn(0, 100)
        }

        private fun round2(value: Double): Double = round(value * 100.0) / 100.0
    }
}
