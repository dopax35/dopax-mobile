package com.pdcollect.app.service

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.core.content.edit
import com.pdcollect.app.data.model.ExternalActivitySample
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * Strava OAuth2 (authorization-code) connect flow + recent-activity fetch.
 *
 * SETUP REQUIRED before this works (programmer action, not done by this code):
 *  1. Register a free app at https://www.strava.com/settings/api to get a
 *     Client ID + Client Secret. Fill both into CLIENT_ID / CLIENT_SECRET below.
 *  2. In that same Strava app settings page, set "Authorization Callback
 *     Domain" to exactly "strava-callback" (no scheme, no slashes) — Strava
 *     requires redirect_uri to be "<your_scheme>://<callback_domain>", so
 *     this pairs with the "pdcollect" scheme + intent filter already added
 *     to AndroidManifest.xml.
 *  3. Strava's OAuth implementation is not fully spec-compliant for native
 *     custom-scheme redirects — developers have reported needing to test on
 *     a real device and sometimes adjust the exact redirect_uri casing/format
 *     to stop Strava returning "invalid redirect_uri". Budget time to debug
 *     this against a live Strava app registration.
 *
 * SECURITY NOTE: embedding CLIENT_SECRET in the app binary means it can be
 * extracted from the APK. Since this app already uses Firebase, consider
 * moving exchangeCodeForToken()/refresh into a Cloud Function so the secret
 * never ships to devices — this file keeps it client-side to stay a
 * drop-in, backend-free starting point.
 */
object StravaManager {

    private const val CLIENT_ID = "REPLACE_WITH_STRAVA_CLIENT_ID"
    private const val CLIENT_SECRET = "REPLACE_WITH_STRAVA_CLIENT_SECRET"
    private const val REDIRECT_URI = "pdcollect://strava-callback"
    private const val PREFS = "strava_prefs"

    private val httpClient = OkHttpClient()

    fun isConnected(context: Context): Boolean =
        prefs(context).getString("refresh_token", null) != null

    fun startAuth(context: Context) {
        // Fail fast with a clear message rather than round-tripping to
        // Strava's servers and showing whatever cryptic page/JSON they
        // return for an unregistered client_id.
        if (CLIENT_ID == "REPLACE_WITH_STRAVA_CLIENT_ID" || CLIENT_ID.isBlank()) {
            Toast.makeText(
                context,
                "Strava isn't set up in this build yet (no API credentials configured).",
                Toast.LENGTH_LONG
            ).show()
            return
        }
        val url = "https://www.strava.com/oauth/mobile/authorize" +
            "?client_id=$CLIENT_ID" +
            "&redirect_uri=${Uri.encode(REDIRECT_URI)}" +
            "&response_type=code" +
            "&approval_prompt=auto" +
            "&scope=activity:read_all"
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    }

    /**
     * Call from the activity that owns the pdcollect://strava-callback
     * intent filter. Returns null on success, or a human-readable reason on
     * failure — previously this returned a bare Boolean that was `true` as
     * soon as a "code" query param was present, regardless of whether the
     * token exchange that followed actually succeeded, so
     * StravaAuthCallbackActivity always toasted "Strava connected." even
     * when it demonstrably hadn't (e.g. the placeholder credentials above,
     * or any other exchange failure).
     */
    suspend fun handleAuthRedirect(context: Context, uri: Uri): String? {
        if (uri.scheme != "pdcollect" || uri.host != "strava-callback") return "Unrecognized redirect."
        val deniedReason = uri.getQueryParameter("error")
        if (deniedReason != null) {
            return if (deniedReason == "access_denied") "Strava access wasn't granted."
                   else "Strava sign-in failed ($deniedReason)."
        }
        val code = uri.getQueryParameter("code") ?: return "Strava didn't return an authorization code."
        return exchangeCodeForToken(context, code)
    }

    /** Returns null on success, or a human-readable error message on failure. */
    private suspend fun exchangeCodeForToken(context: Context, code: String): String? =
        withContext(Dispatchers.IO) {
            val body = FormBody.Builder()
                .add("client_id", CLIENT_ID)
                .add("client_secret", CLIENT_SECRET)
                .add("code", code)
                .add("grant_type", "authorization_code")
                .build()
            val request = Request.Builder().url("https://www.strava.com/oauth/token").post(body).build()
            try {
                httpClient.newCall(request).execute().use { resp ->
                    val json = JSONObject(resp.body?.string().orEmpty())
                    if (!resp.isSuccessful) return@withContext describeStravaError(json)
                    saveTokens(context, json)
                }
            } catch (_: Exception) {
                "Couldn't reach Strava. Check your connection and try again."
            }
        }

    /**
     * Stores tokens from a successful exchange, or reports why it wasn't
     * actually successful. Strava's error response is 400-range JSON like
     * {"message":"Bad Request","errors":[{"resource":"Application","field":"client_id","code":"invalid"}]} —
     * previously this was stored via optString(), which returns "" (not
     * null) for a missing key, so a failed exchange silently wrote an empty
     * access_token/refresh_token and isConnected() — which just checks
     * "is refresh_token non-null" — would incorrectly flip to true forever
     * after any failure, since SharedPreferences doesn't distinguish an
     * empty string from a real one.
     */
    private fun saveTokens(context: Context, json: JSONObject): String? {
        val accessToken = json.optString("access_token").takeIf { it.isNotBlank() }
        val refreshToken = json.optString("refresh_token").takeIf { it.isNotBlank() }
        if (accessToken == null || refreshToken == null) {
            return describeStravaError(json)
        }
        prefs(context).edit {
            putString("access_token", accessToken)
            putString("refresh_token", refreshToken)
            putLong("expires_at", json.optLong("expires_at"))
        }
        return null
    }

    private fun describeStravaError(json: JSONObject): String {
        val firstError = json.optJSONArray("errors")?.optJSONObject(0)
        val field = firstError?.optString("field")?.takeIf { it.isNotBlank() }
        val code = firstError?.optString("code")?.takeIf { it.isNotBlank() }
        val message = json.optString("message").takeIf { it.isNotBlank() } ?: "Strava sign-in failed."
        val detail = listOfNotNull(field, code).joinToString(" ")
        return if (detail.isEmpty()) message else "$message ($detail)"
    }

    private suspend fun ensureFreshAccessToken(context: Context): String? = withContext(Dispatchers.IO) {
        val p = prefs(context)
        val refreshToken = p.getString("refresh_token", null) ?: return@withContext null
        val expiresAt = p.getLong("expires_at", 0)
        val access = p.getString("access_token", null)
        if (access != null && Instant.now().epochSecond < expiresAt - 60) return@withContext access

        val body = FormBody.Builder()
            .add("client_id", CLIENT_ID)
            .add("client_secret", CLIENT_SECRET)
            .add("grant_type", "refresh_token")
            .add("refresh_token", refreshToken)
            .build()
        val request = Request.Builder().url("https://www.strava.com/oauth/token").post(body).build()
        try {
            httpClient.newCall(request).execute().use { resp ->
                if (!resp.isSuccessful) return@withContext null
                val json = JSONObject(resp.body?.string().orEmpty())
                saveTokens(context, json)
                json.optString("access_token")
            }
        } catch (_: Exception) { null }
    }

    suspend fun fetchRecentActivities(context: Context, days: Int = 7): List<ExternalActivitySample> {
        val token = ensureFreshAccessToken(context) ?: return emptyList()
        val after = Instant.now().minus(days.toLong(), ChronoUnit.DAYS).epochSecond
        val request = Request.Builder()
            .url("https://www.strava.com/api/v3/athlete/activities?after=$after&per_page=50")
            .addHeader("Authorization", "Bearer $token")
            .build()
        return withContext(Dispatchers.IO) {
            try {
                httpClient.newCall(request).execute().use { resp ->
                    if (!resp.isSuccessful) return@withContext emptyList()
                    val arr = JSONArray(resp.body?.string().orEmpty())
                    (0 until arr.length()).map { i ->
                        val a = arr.getJSONObject(i)
                        val startEpochMs = Instant.parse(a.getString("start_date")).toEpochMilli()
                        val kj = a.optDouble("kilojoules", Double.NaN)
                        val hr = a.optDouble("average_heartrate", Double.NaN)
                        // Strava's numeric activity id, stringified for
                        // import dedup. optLong defaults to 0 if the field
                        // is ever missing/malformed; real Strava ids are
                        // always large positive numbers, so "0" is treated
                        // as "no usable id" (blank) rather than a real one.
                        val idRaw = a.optLong("id", 0L)
                        ExternalActivitySample(
                            timestampMs = System.currentTimeMillis(),
                            activityType = mapStravaType(a.optString("type")),
                            timeOfDayMs = startEpochMs,
                            durationMin = a.optInt("moving_time", 0) / 60.0,
                            calories = if (kj.isNaN()) null else kj * 0.239006, // kJ -> kcal
                            avgHeartRate = if (hr.isNaN()) null else hr,
                            externalId = if (idRaw > 0) idRaw.toString() else ""
                        )
                    }
                }
            } catch (_: Exception) {
                emptyList()
            }
        }
    }

    private fun mapStravaType(type: String): String {
        val t = type.lowercase()
        if (t.contains("run")) return "Running"
        if (t.contains("ride") || t.contains("cycl") || t.contains("bike")) return "Bike"
        if (t.contains("swim")) return "Swimming"
        if (t.contains("weight") || t.contains("strength") || t.contains("workout")) return "Weight Training"
        if (t.contains("yoga") || t.contains("pilates")) return "Pilates"
        return "Other"
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
