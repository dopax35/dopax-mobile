package com.pdcollect.app.data

import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.tasks.await

object FirebaseSyncManager {
    private val db = FirebaseFirestore.getInstance()

    // Firestore enforces a hard 1 MiB per-document size cap. getCachedDashboardMetrics()
    // defaults to trendDays=0, which DashboardSummaryStore treats as *unbounded* — every
    // day since the participant started the study. For a long-running participant that
    // can silently exceed the cap, after which every subsequent saveProfileToCloud() call
    // fails from then on (caught below — no crash, but no user-visible error either, so
    // cloud dashboard sync just quietly stops working). Bounding both the date window and
    // the per-series point count keeps this well within the cap; the on-device dashboard
    // itself never needs more than a few months of trend to render anyway.
    private const val MAX_TREND_DAYS_FOR_CLOUD = 90
    private const val MAX_TREND_POINTS_PER_SERIES = 90

    suspend fun saveProfileToCloud(profile: UserProfile, dataManager: DataManager? = null): Boolean {
        val user = FirebaseAuth.getInstance().currentUser
        val uid = user?.uid ?: return false
        return try {
            val data = profile.toMap().toMutableMap()
            data["email"] = user.email ?: ""
            data["lastSyncTime"] = System.currentTimeMillis()

            if (dataManager != null) {
                // Upload local cache for graphs — bounded, see constants above.
                val metrics = dataManager.getCachedDashboardMetrics(trendDays = MAX_TREND_DAYS_FOR_CLOUD)
                val trendsMap = mutableMapOf<String, List<Map<String, Any>>>()
                metrics.testTrend.forEach { series ->
                    trendsMap[series.name] = series.points.takeLast(MAX_TREND_POINTS_PER_SERIES)
                        .map { mapOf("date" to it.label, "value" to it.value) }
                }
                metrics.gaitTrend.forEach { series ->
                    trendsMap[series.name] = series.points.takeLast(MAX_TREND_POINTS_PER_SERIES)
                        .map { mapOf("date" to it.label, "value" to it.value) }
                }
                data["dashboardMetrics"] = trendsMap
            }

            db.collection("users").document(uid).set(data).await()
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    suspend fun loadProfileFromCloud(profile: UserProfile): Boolean {
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return false
        return try {
            val snapshot = db.collection("users").document(uid).get().await()
            if (snapshot.exists()) {
                val data = snapshot.data ?: return false
                profile.updateFromMap(data)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}
