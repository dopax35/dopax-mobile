package com.pdcollect.app.service

import android.bluetooth.le.ScanResult
import java.util.Locale

object BeanieDiscovery {
    private val beanieKeywords = listOf("beanie", "nrf", "v3", "v4", "v4e")

    @Suppress("MissingPermission")
    fun displayName(result: ScanResult): String {
        return result.scanRecord?.deviceName
            ?: result.device.name
            ?: "Unknown"
    }

    fun isLikelyBeanie(result: ScanResult): Boolean {
        val name = displayName(result)
        if (isLikelyBeanieName(name)) return true
        return result.scanRecord?.serviceUuids?.any { it.uuid == BeanieService.BEANIE_SERVICE_UUID } == true
    }

    fun isLikelyBeanieName(name: String): Boolean {
        val lower = name.trim().lowercase(Locale.US)
        return beanieKeywords.any { lower.contains(it) }
    }

    fun matchesSavedDevice(result: ScanResult, savedAddress: String, savedName: String): Boolean {
        val address = result.device.address
        val scannedName = displayName(result)
        val hasBeanieService = result.scanRecord?.serviceUuids?.any {
            it.uuid == BeanieService.BEANIE_SERVICE_UUID
        } == true
        return matchesSavedDeviceIdentity(
            address = address,
            scannedName = scannedName,
            advertisesBeanieService = hasBeanieService,
            savedAddress = savedAddress,
            savedName = savedName
        )
    }

    internal fun matchesSavedDeviceIdentity(
        address: String,
        scannedName: String,
        advertisesBeanieService: Boolean,
        savedAddress: String,
        savedName: String
    ): Boolean {
        if (savedAddress.isNotBlank() && address.equals(savedAddress, ignoreCase = true)) {
            return true
        }
        if (savedName.isNotBlank() && sameDeviceName(scannedName, savedName)) {
            return true
        }
        if (savedAddress.isNotBlank() || savedName.isNotBlank()) {
            return false
        }
        return advertisesBeanieService || isLikelyBeanieName(scannedName)
    }

    private fun sameDeviceName(left: String, right: String): Boolean {
        val normalizedLeft = normalizeDeviceName(left)
        val normalizedRight = normalizeDeviceName(right)
        if (normalizedLeft.isBlank() || normalizedRight.isBlank()) return false
        return normalizedLeft == normalizedRight ||
            normalizedLeft.replace(" ", "") == normalizedRight.replace(" ", "")
    }

    private fun normalizeDeviceName(name: String): String {
        var normalized = name
            .trim()
            .lowercase(Locale.US)
            .replace(Regex("[^a-z0-9]+"), " ")
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
