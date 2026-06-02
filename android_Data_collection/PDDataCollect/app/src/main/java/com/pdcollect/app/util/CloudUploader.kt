package com.pdcollect.app.util

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.util.concurrent.TimeUnit
import org.json.JSONObject

object CloudUploader {
    // Google Apps Script Web App URL for DopaX Data Upload API
    const val APPS_SCRIPT_WEB_APP_URL = "https://script.google.com/macros/s/AKfycbxwRiXDXhUmKER4wdplH2lwtEeLXDlKfP0AZQaU2fqzcmgwjD7NHAr_RkDHdUsTgudXQw/exec"

    // Target Google Drive folder where uploaded ZIPs are stored.
    // The Apps Script reads this folderId from the request and creates the file there.
    const val TARGET_DRIVE_FOLDER_ID = "1QLsYUTmXIha7rn7wNIJDXVTtrcWoXdly"

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.MINUTES) // 1-2 GB streams take significant time
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    fun uploadZipFileSync(zipFile: File, userId: String, dateStr: String): Boolean {
        val zipBytes = zipFile.length()
        if (!zipFile.exists() || zipBytes <= 0L || APPS_SCRIPT_WEB_APP_URL.contains("YOUR_GOOGLE_APPS_SCRIPT")) {
            return false
        }
        val filename = UploadState.cloudFilename(userId, dateStr)

        try {
            // STEP 1: Request Direct Resumable Upload URL from our Web App
            val getUrlJson = JSONObject().apply {
                put("action", "getUploadUrl")
                put("filename", filename)
                put("folderId", TARGET_DRIVE_FOLDER_ID)
                put("mimeType", "application/zip")
                put("contentLength", zipBytes)
                put("uploadSessionId", UploadState.uploadSessionId(userId, dateStr, zipBytes))
                put("replaceExisting", true)
            }
            
            val authRequest = Request.Builder()
                .url(APPS_SCRIPT_WEB_APP_URL)
                .post(getUrlJson.toString().toRequestBody("application/json".toMediaType()))
                .build()
                
            val responseBody = client.newCall(authRequest).execute().use { authResponse ->
                if (!authResponse.isSuccessful) return false
                authResponse.body?.string() ?: return false
            }
            
            val jsonResponse = try { JSONObject(responseBody) } catch (e: Exception) { return false }
            if (!jsonResponse.has("uploadUrl")) return false
            val uploadUrl = jsonResponse.getString("uploadUrl")
            
            // STEP 2: Stream the File directly to Google Cloud Storage (Zero RAM cost)
            val fileBody = zipFile.asRequestBody("application/zip".toMediaType())
            val uploadRequest = Request.Builder()
                .url(uploadUrl)
                .put(fileBody) // Google Resumable APIs use PUT for stream
                .build()
                
            val streamSuccess = client.newCall(uploadRequest).execute().use { streamResponse ->
                streamResponse.isSuccessful
            }
            if (!streamSuccess) return false
            
            // STEP 3: Notify Web App that upload is complete to fire email
            val notifyJson = JSONObject().apply {
                put("action", "notify")
                put("userId", userId)
                put("filename", filename)
                put("folderId", TARGET_DRIVE_FOLDER_ID)
                put("contentLength", zipBytes)
                put("uploadSessionId", UploadState.uploadSessionId(userId, dateStr, zipBytes))
            }
            
            val notifyRequest = Request.Builder()
                .url(APPS_SCRIPT_WEB_APP_URL)
                .post(notifyJson.toString().toRequestBody("application/json".toMediaType()))
                .build()
                
            val notifySuccess = runCatching {
                client.newCall(notifyRequest).execute().use { notifyResponse ->
                    notifyResponse.isSuccessful
                }
            }.getOrDefault(false)
            if (!notifySuccess) {
                android.util.Log.w("CloudUploader", "Upload stream succeeded but notify failed for $filename")
            }

            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }
}
