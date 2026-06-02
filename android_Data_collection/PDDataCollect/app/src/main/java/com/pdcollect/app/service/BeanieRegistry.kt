package com.pdcollect.app.service

import java.util.Locale

data class BeanieProfile(
    val name: String,
    val c1: Double,
    val heatFluxK: Double,
    val needsSensorSwap: Boolean
)

object BeanieRegistry {
    private val defaultProfile = BeanieProfile(
        name = "Default",
        c1 = 3.0,
        heatFluxK = 0.02,
        needsSensorSwap = true
    )

    private val profiles = listOf(
        BeanieProfile("Pink2", 4.00, 0.0202, false),
        BeanieProfile("Pink1", 3.64, 0.0184, false),
        BeanieProfile("Blue1", 3.75, 0.0189, false),
        BeanieProfile("Pink3", 1.80, 0.0120, true),
        BeanieProfile("Black 04", 2.25, 0.01135, true),
        BeanieProfile("Yoel's Beanie", 3.17, 0.01362, true),
        BeanieProfile("Gabriel's Beanie", 2.0, 0.0080, true),
        BeanieProfile("Trevor's Beanie", 2.45, 0.0120, true),
        BeanieProfile("Black 08", 2.54, 0.0120, true),
        BeanieProfile("Hefner's Beanie", 2.40, 0.0130, true),
        BeanieProfile("Kong's Beanie", 3.79, 0.0190, true),
        BeanieProfile("Anantha's Beanie", 2.70, 0.01362, true),
        BeanieProfile("Scotty!", 3.5, 0.0175, true),
        BeanieProfile("Rosanne's Beanie", 2.4, 0.0120, true),
        BeanieProfile("Ori's Beanie", 2.7, 0.01362, false)
    )

    fun profileForDevice(deviceName: String): BeanieProfile {
        val normalizedDeviceName = normalizeName(deviceName)
        if (normalizedDeviceName.isBlank()) return defaultProfile
        return profiles.find { profile ->
            val normalizedProfileName = normalizeName(profile.name)
            normalizedDeviceName == normalizedProfileName ||
                normalizedDeviceName.contains(normalizedProfileName) ||
                normalizedProfileName.contains(normalizedDeviceName)
        } ?: defaultProfile
    }

    private fun normalizeName(name: String): String {
        var normalized = name
            .trim()
            .lowercase(Locale.US)
            .replace(Regex("[_-]+"), " ")
            .replace(Regex("\\s+"), " ")
            .trim()

        var previous: String
        do {
            previous = normalized
            normalized = normalized
                .replace(Regex("^(v\\d+[a-z0-9]*|nrf\\d*|beanie)\\s+"), "")
                .trim()
        } while (normalized != previous)

        return normalized
    }
}
