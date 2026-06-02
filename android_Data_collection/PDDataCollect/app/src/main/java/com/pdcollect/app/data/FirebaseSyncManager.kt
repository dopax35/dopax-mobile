package com.pdcollect.app.data

import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.tasks.await

object FirebaseSyncManager {
    private val db = FirebaseFirestore.getInstance()

    suspend fun saveProfileToCloud(profile: UserProfile, dataManager: DataManager? = null): Boolean {
        val user = FirebaseAuth.getInstance().currentUser
        val uid = user?.uid ?: return false
        return try {
            val data = profile.toMap().toMutableMap()
            data["email"] = user.email ?: ""
            data["lastSyncTime"] = System.currentTimeMillis()
            
            if (dataManager != null) {
                // Upload local cache for graphs
                val metrics = dataManager.getCachedDashboardMetrics()
                val trendsMap = mutableMapOf<String, List<Map<String, Any>>>()
                metrics.testTrend.forEach { series ->
                    trendsMap[series.name] = series.points.map { mapOf("date" to it.label, "value" to it.value) }
                }
                metrics.gaitTrend.forEach { series ->
                    trendsMap[series.name] = series.points.map { mapOf("date" to it.label, "value" to it.value) }
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
