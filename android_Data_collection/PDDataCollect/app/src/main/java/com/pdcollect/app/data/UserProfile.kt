package com.pdcollect.app.data

import android.annotation.SuppressLint
import android.content.Context
import com.pdcollect.app.util.Constants

class UserProfile(context: Context) {
    private val prefs = context.getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE)

    var consentGiven: Boolean
        get() = prefs.getBoolean(Constants.PREF_CONSENT_GIVEN, false)
        set(value) = prefs.edit().putBoolean(Constants.PREF_CONSENT_GIVEN, value).apply()

    var signatureName: String
        get() = prefs.getString("signature_name", "") ?: ""
        set(value) = prefs.edit().putString("signature_name", value).apply()

    var consentTimestamp: Long
        get() = prefs.getLong("consent_timestamp", 0L)
        set(value) = prefs.edit().putLong("consent_timestamp", value).apply()

    var shellyMacAddress: String
        get() = prefs.getString("shelly_mac_address", "") ?: ""
        set(value) = prefs.edit().putString("shelly_mac_address", value).apply()

    var profileComplete: Boolean
        get() = prefs.getBoolean(Constants.PREF_PROFILE_COMPLETE, false)
        set(value) = prefs.edit().putBoolean(Constants.PREF_PROFILE_COMPLETE, value).apply()

    var userId: String
        get() {
            val currentId = prefs.getString(Constants.PREF_USER_ID, "") ?: ""
            if (currentId.isEmpty()) {
                val newId = java.util.UUID.randomUUID().toString().substring(0, 6).uppercase()
                prefs.edit().putString(Constants.PREF_USER_ID, newId).apply()
                return newId
            }
            return currentId
        }
        set(value) = prefs.edit().putString(Constants.PREF_USER_ID, value).apply()

    var age: Int
        get() = prefs.getInt(Constants.PREF_AGE, 0)
        set(value) = prefs.edit().putInt(Constants.PREF_AGE, value).apply()

    var gender: String
        get() = prefs.getString(Constants.PREF_GENDER, "") ?: ""
        set(value) = prefs.edit().putString(Constants.PREF_GENDER, value).apply()

    // Stored as JSON string: [{"name":"Levodopa","dose":"100mg"},...]
    var medications: String
        get() = prefs.getString(Constants.PREF_MEDICATIONS, "[]") ?: "[]"
        set(value) = prefs.edit().putString(Constants.PREF_MEDICATIONS, value).apply()

    var keyloggingEnabled: Boolean
        get() = prefs.getBoolean(Constants.PREF_KEYLOGGING_ENABLED, true)
        set(value) = prefs.edit().putBoolean(Constants.PREF_KEYLOGGING_ENABLED, value).apply()

    var faceDistanceEnabled: Boolean
        get() = faceDistanceMode != Constants.FACE_DISTANCE_MODE_OFF
        set(value) {
            val nextMode = if (value) {
                if (faceDistanceMode == Constants.FACE_DISTANCE_MODE_OFF) {
                    Constants.FACE_DISTANCE_MODE_APP_FOREGROUND
                } else {
                    faceDistanceMode
                }
            } else {
                Constants.FACE_DISTANCE_MODE_OFF
            }
            prefs.edit()
                .putBoolean(Constants.PREF_FACE_DISTANCE_ENABLED, value)
                .putString(Constants.PREF_FACE_DISTANCE_MODE, nextMode)
                .apply()
        }

    var faceDistanceMode: String
        get() {
            val stored = prefs.getString(Constants.PREF_FACE_DISTANCE_MODE, null)
            if (stored != null) return stored

            return Constants.FACE_DISTANCE_MODE_ALWAYS
        }
        set(value) {
            val normalized = when (value) {
                Constants.FACE_DISTANCE_MODE_APP_FOREGROUND,
                Constants.FACE_DISTANCE_MODE_ALWAYS,
                Constants.FACE_DISTANCE_MODE_TMT_ONLY -> value
                else -> Constants.FACE_DISTANCE_MODE_OFF
            }
            prefs.edit()
                .putString(Constants.PREF_FACE_DISTANCE_MODE, normalized)
                .putBoolean(Constants.PREF_FACE_DISTANCE_ENABLED, normalized != Constants.FACE_DISTANCE_MODE_OFF)
                .apply()
        }

    var passiveCollectionActive: Boolean
        get() = prefs.getBoolean(Constants.PREF_PASSIVE_COLLECTION_ACTIVE, true)
        set(value) = prefs.edit().putBoolean(Constants.PREF_PASSIVE_COLLECTION_ACTIVE, value).apply()

    var autoUploadEnabled: Boolean
        get() = prefs.getBoolean(Constants.PREF_AUTO_UPLOAD_ENABLED, true)
        set(value) = prefs.edit().putBoolean(Constants.PREF_AUTO_UPLOAD_ENABLED, value).apply()

    var testTimeMorning: String
        get() = prefs.getString(Constants.PREF_TEST_TIME_MORNING, "08:00") ?: "08:00"
        set(value) = prefs.edit().putString(Constants.PREF_TEST_TIME_MORNING, value).apply()

    var testTimeNoon: String
        get() = prefs.getString(Constants.PREF_TEST_TIME_NOON, "12:00") ?: "12:00"
        set(value) = prefs.edit().putString(Constants.PREF_TEST_TIME_NOON, value).apply()

    var testTimeRandom: String
        get() = prefs.getString(Constants.PREF_TEST_TIME_RANDOM, "") ?: ""
        set(value) = prefs.edit().putString(Constants.PREF_TEST_TIME_RANDOM, value).apply()

    var hrDeviceAddress: String
        get() = prefs.getString(Constants.PREF_HR_DEVICE_ADDRESS, "") ?: ""
        set(value) = prefs.edit().putString(Constants.PREF_HR_DEVICE_ADDRESS, value).apply()

    var hrDeviceName: String
        get() = prefs.getString(Constants.PREF_HR_DEVICE_NAME, "") ?: ""
        set(value) = prefs.edit().putString(Constants.PREF_HR_DEVICE_NAME, value).apply()

    var beanieDeviceAddress: String
        get() = prefs.getString(Constants.PREF_BEANIE_DEVICE_ADDRESS, "") ?: ""
        set(value) = prefs.edit().putString(Constants.PREF_BEANIE_DEVICE_ADDRESS, value).apply()

    var beanieDeviceName: String
        get() = prefs.getString(Constants.PREF_BEANIE_DEVICE_NAME, "") ?: ""
        set(value) = prefs.edit().putString(Constants.PREF_BEANIE_DEVICE_NAME, value).apply()

    /**
     * The participant's dominant hand. Stored as one of
     * [Constants.PARTICIPANT_HAND_RIGHT] / [Constants.PARTICIPANT_HAND_LEFT] /
     * [Constants.PARTICIPANT_HAND_UNKNOWN]. Defaults to Unknown until the
     * participant explicitly answers in profile setup or settings, so we never
     * fabricate handedness data.
     */
    var dominantHand: String
        get() = prefs.getString(Constants.PREF_DOMINANT_HAND, Constants.PARTICIPANT_HAND_UNKNOWN)
            ?: Constants.PARTICIPANT_HAND_UNKNOWN
        set(value) = prefs.edit().putString(Constants.PREF_DOMINANT_HAND, value).apply()

    /**
     * The body side most affected by the participant's PD symptoms, as
     * self-reported. One of [Constants.PARTICIPANT_SIDE_RIGHT] / _LEFT / _BOTH /
     * _NONE / _UNKNOWN. _NONE is a legitimate value (e.g. control participants
     * or pre-symptomatic recruits); _UNKNOWN means "not asked yet".
     */
    var affectedSide: String
        get() = prefs.getString(Constants.PREF_AFFECTED_SIDE, Constants.PARTICIPANT_SIDE_UNKNOWN)
            ?: Constants.PARTICIPANT_SIDE_UNKNOWN
        set(value) = prefs.edit().putString(Constants.PREF_AFFECTED_SIDE, value).apply()

    var hasSeenWalkthrough: Boolean
        get() = prefs.getBoolean(Constants.PREF_HAS_SEEN_WALKTHROUGH, false)
        set(value) = prefs.edit().putBoolean(Constants.PREF_HAS_SEEN_WALKTHROUGH, value).apply()

    /**
     * Wipe every preference this app has stored. Used by the Withdraw flow.
     * Uses commit() (not apply()) so the caller can rely on the file being
     * gone before continuing — the next read will produce defaults and a
     * fresh user ID.
     */
    @SuppressLint("ApplySharedPref")
    fun clearAll(): Boolean = prefs.edit().clear().commit()

    fun toMap(): Map<String, Any> {
        return mapOf(
            "consentGiven" to consentGiven,
            "signatureName" to signatureName,
            "consentTimestamp" to consentTimestamp,
            "shellyMacAddress" to shellyMacAddress,
            "profileComplete" to profileComplete,
            "userId" to userId,
            "age" to age,
            "gender" to gender,
            "medications" to medications,
            "keyloggingEnabled" to keyloggingEnabled,
            "faceDistanceMode" to faceDistanceMode,
            "passiveCollectionActive" to passiveCollectionActive,
            "autoUploadEnabled" to autoUploadEnabled,
            "testTimeMorning" to testTimeMorning,
            "testTimeNoon" to testTimeNoon,
            "testTimeRandom" to testTimeRandom,
            "hrDeviceAddress" to hrDeviceAddress,
            "hrDeviceName" to hrDeviceName,
            "beanieDeviceAddress" to beanieDeviceAddress,
            "beanieDeviceName" to beanieDeviceName,
            "dominantHand" to dominantHand,
            "affectedSide" to affectedSide,
            "hasSeenWalkthrough" to hasSeenWalkthrough
        )
    }

    fun updateFromMap(map: Map<String, Any>) {
        val editor = prefs.edit()
        (map["consentGiven"] as? Boolean)?.let { editor.putBoolean(Constants.PREF_CONSENT_GIVEN, it) }
        (map["signatureName"] as? String)?.let { editor.putString("signature_name", it) }
        (map["consentTimestamp"] as? Long)?.let { editor.putLong("consent_timestamp", it) }
        (map["shellyMacAddress"] as? String)?.let { editor.putString("shelly_mac_address", it) }
        (map["profileComplete"] as? Boolean)?.let { editor.putBoolean(Constants.PREF_PROFILE_COMPLETE, it) }
        (map["userId"] as? String)?.let { editor.putString(Constants.PREF_USER_ID, it) }
        (map["age"] as? Long)?.let { editor.putInt(Constants.PREF_AGE, it.toInt()) }
        (map["gender"] as? String)?.let { editor.putString(Constants.PREF_GENDER, it) }
        (map["medications"] as? String)?.let { editor.putString(Constants.PREF_MEDICATIONS, it) }
        (map["keyloggingEnabled"] as? Boolean)?.let { editor.putBoolean(Constants.PREF_KEYLOGGING_ENABLED, it) }
        (map["faceDistanceMode"] as? String)?.let { editor.putString(Constants.PREF_FACE_DISTANCE_MODE, it) }
        (map["passiveCollectionActive"] as? Boolean)?.let { editor.putBoolean(Constants.PREF_PASSIVE_COLLECTION_ACTIVE, it) }
        (map["autoUploadEnabled"] as? Boolean)?.let { editor.putBoolean(Constants.PREF_AUTO_UPLOAD_ENABLED, it) }
        (map["testTimeMorning"] as? String)?.let { editor.putString(Constants.PREF_TEST_TIME_MORNING, it) }
        (map["testTimeNoon"] as? String)?.let { editor.putString(Constants.PREF_TEST_TIME_NOON, it) }
        (map["testTimeRandom"] as? String)?.let { editor.putString(Constants.PREF_TEST_TIME_RANDOM, it) }
        (map["hrDeviceAddress"] as? String)?.let { editor.putString(Constants.PREF_HR_DEVICE_ADDRESS, it) }
        (map["hrDeviceName"] as? String)?.let { editor.putString(Constants.PREF_HR_DEVICE_NAME, it) }
        (map["beanieDeviceAddress"] as? String)?.let { editor.putString(Constants.PREF_BEANIE_DEVICE_ADDRESS, it) }
        (map["beanieDeviceName"] as? String)?.let { editor.putString(Constants.PREF_BEANIE_DEVICE_NAME, it) }
        (map["dominantHand"] as? String)?.let { editor.putString(Constants.PREF_DOMINANT_HAND, it) }
        (map["affectedSide"] as? String)?.let { editor.putString(Constants.PREF_AFFECTED_SIDE, it) }
        (map["hasSeenWalkthrough"] as? Boolean)?.let { editor.putBoolean(Constants.PREF_HAS_SEEN_WALKTHROUGH, it) }
        editor.apply()
    }
}
