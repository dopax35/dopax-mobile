package com.pdcollect.app.data

import android.content.Context
import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.pdcollect.app.util.Constants
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Additive dual-write to the Postgres backend (§7.1 / Phase 3).
 * Firestore remains primary while BOTH_ARCH=true — failures never block onboarding.
 */
object BackendSyncManager {
    private const val TAG = "BackendSyncManager"
    private const val PREF_TOKEN = "dopax_backend_access_token"
    private const val PREF_REVISION = "dopax_backend_profile_revision"
    private const val PREF_BASE_URL = "dopax_backend_base_url"

    private val executor = Executors.newSingleThreadExecutor()

    /** Override via SharedPreferences for device testing; default laptop/emulator. */
    fun baseUrl(context: Context): String {
        val prefs = context.getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE)
        val override = prefs.getString(PREF_BASE_URL, null)
        if (!override.isNullOrBlank()) return override.trimEnd('/')
        // Android emulator → host machine
        return "http://10.0.2.2:8080"
    }

    fun ensureSession(context: Context, preferredCode: String, onDone: ((Boolean) -> Unit)? = null) {
        val user = FirebaseAuth.getInstance().currentUser
        if (user == null) {
            onDone?.invoke(false)
            return
        }

        user.getIdToken(false).addOnCompleteListener { task ->
            if (!task.isSuccessful || task.result?.token.isNullOrBlank()) {
                onDone?.invoke(false)
                return@addOnCompleteListener
            }
            val idToken = task.result!!.token!!
            executor.execute {
                val body = JSONObject()
                    .put("idToken", idToken)
                    .put("preferredParticipantCode", preferredCode)
                val (code, json) = request(context, "POST", "/v1/auth/session", body, authorized = false)
                val ok = code in 200..299
                if (ok) {
                    json.optString("token").takeIf { it.isNotBlank() }?.let { saveToken(context, it) }
                    json.optJSONObject("profile")?.optInt("revision", 0)?.takeIf { it > 0 }
                        ?.let { saveRevision(context, it) }
                }
                onDone?.let { cb -> android.os.Handler(android.os.Looper.getMainLooper()).post { cb(ok) } }
            }
        }
    }

    fun syncConsent(context: Context, signatureName: String, onDone: ((Boolean) -> Unit)? = null) {
        val profile = UserProfile(context)
        ensureSession(context, profile.userId) { ok ->
            if (!ok) {
                onDone?.invoke(false)
                return@ensureSession
            }
            executor.execute {
                val body = JSONObject()
                    .put("signatureName", signatureName.ifBlank { "participant" })
                    .put("documentVersion", "onboarding-v2")
                    .put("platform", "android")
                val (code, _) = request(context, "POST", "/v1/participants/me/consent", body, authorized = true)
                onDone?.let { cb ->
                    android.os.Handler(android.os.Looper.getMainLooper()).post { cb(code in 200..299) }
                }
            }
        }
    }

    fun syncProfile(context: Context, onDone: ((Boolean) -> Unit)? = null) {
        val profile = UserProfile(context)
        ensureSession(context, profile.userId) { ok ->
            if (!ok) {
                onDone?.invoke(false)
                return@ensureSession
            }
            executor.execute {
                val meds = try {
                    JSONArray(profile.medications)
                } catch (_: Exception) {
                    JSONArray()
                }
                val body = JSONObject()
                    .put("revision", knownRevision(context))
                    .put("age", profile.age)
                    .put("gender", profile.gender)
                    .put("dominantHand", profile.dominantHand)
                    .put("affectedSide", profile.affectedSide)
                    .put("signatureName", profile.signatureName)
                    .put("medications", meds)
                    .put("profileComplete", profile.profileComplete)
                    .put("onboardingVersion", profile.onboardingVersion)
                    .put(
                        "sessionWindows",
                        JSONObject()
                            .put("morning", profile.testTimeMorning)
                            .put("noon", profile.testTimeNoon)
                            .put("random", profile.testTimeRandom)
                            .put("custom", profile.testTimeCustom),
                    )
                    .put(
                        "healthConnections",
                        JSONObject()
                            .put("healthConnect", profile.healthConnectStatus)
                            .put("googleFit", profile.healthGoogleFitStatus)
                            .put("strava", profile.healthStravaStatus),
                    )
                    .put(
                        "permissions",
                        JSONObject()
                            .put("notifications", profile.notificationsOptIn)
                            .put("usageAccess", profile.usageAccessOptIn)
                            .put("exactAlarm", profile.exactAlarmOptIn)
                            .put("interactionLogging", profile.keyloggingEnabled),
                    )

                // signatureName above stays the consent signature; the onboarding
                // display name is a separate, optional field.
                if (profile.displayName.isNotBlank()) {
                    body.put("displayName", profile.displayName)
                }
                profile.yearOfBirth.toIntOrNull()?.takeIf { it in 1900..2100 }?.let {
                    body.put("yearOfBirth", it)
                }

                val (code, json) = request(
                    context,
                    "PUT",
                    "/v1/participants/me/profile",
                    body,
                    authorized = true,
                )
                if (code in 200..299) {
                    json.optJSONObject("profile")?.optInt("revision", 0)?.takeIf { it > 0 }
                        ?.let { saveRevision(context, it) }
                } else if (code == 409) {
                    json.optJSONObject("profile")?.optInt("revision", 0)?.takeIf { it > 0 }
                        ?.let { saveRevision(context, it) }
                }
                onDone?.let { cb ->
                    android.os.Handler(android.os.Looper.getMainLooper()).post { cb(code in 200..299) }
                }
            }
        }
    }

    private fun knownRevision(context: Context): Int {
        val v = context.getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE)
            .getInt(PREF_REVISION, 1)
        return if (v > 0) v else 1
    }

    private fun saveRevision(context: Context, revision: Int) {
        context.getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putInt(PREF_REVISION, revision).apply()
    }

    private fun saveToken(context: Context, token: String) {
        context.getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(PREF_TOKEN, token).apply()
    }

    private fun token(context: Context): String? =
        context.getSharedPreferences(Constants.PREFS_NAME, Context.MODE_PRIVATE)
            .getString(PREF_TOKEN, null)

    private fun request(
        context: Context,
        method: String,
        path: String,
        body: JSONObject,
        authorized: Boolean,
    ): Pair<Int, JSONObject> {
        return try {
            val url = URL(baseUrl(context) + path)
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = method
                connectTimeout = 12_000
                readTimeout = 12_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                if (authorized) {
                    token(context)?.let { setRequestProperty("Authorization", "Bearer $it") }
                }
            }
            OutputStreamWriter(conn.outputStream).use { it.write(body.toString()) }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val text = stream?.let { BufferedReader(InputStreamReader(it)).readText() }.orEmpty()
            val json = if (text.isNotBlank()) JSONObject(text) else JSONObject()
            Pair(code, json)
        } catch (e: Exception) {
            Log.w(TAG, "backend request failed: $method $path", e)
            Pair(0, JSONObject())
        }
    }
}
