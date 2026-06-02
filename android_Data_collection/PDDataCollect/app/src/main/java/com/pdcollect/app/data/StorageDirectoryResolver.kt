package com.pdcollect.app.data

import android.content.Context
import com.pdcollect.app.util.Constants
import java.io.File

object StorageDirectoryResolver {
    private val dateDirRegex = Regex("\\d{4}-\\d{2}-\\d{2}")

    fun resolveBaseDir(context: Context, userProfile: UserProfile): File {
        reconcileUserIdToExistingData(context, userProfile)
        return File(storageRoot(context), userProfile.userId).apply { mkdirs() }
    }

    fun migrateUserDirectory(context: Context, fromUserId: String, toUserId: String) {
        if (fromUserId.isBlank() || toUserId.isBlank() || fromUserId == toUserId) return

        val root = storageRoot(context)
        val fromDir = File(root, fromUserId)
        val toDir = File(root, toUserId)
        if (!fromDir.exists() || toDir.exists()) return

        if (fromDir.renameTo(toDir)) return

        if (!toDir.exists()) toDir.mkdirs()
        fromDir.listFiles()?.forEach { child ->
            child.renameTo(File(toDir, child.name))
        }
        runCatching { fromDir.deleteRecursively() }
    }

    private fun reconcileUserIdToExistingData(context: Context, userProfile: UserProfile) {
        val root = storageRoot(context)
        val currentId = userProfile.userId
        val currentDir = File(root, currentId)
        if (containsRecordedData(currentDir)) return

        val candidates = root.listFiles()
            ?.filter { it.isDirectory && it.name != currentId && containsRecordedData(it) }
            .orEmpty()

        if (candidates.size == 1) {
            userProfile.userId = candidates.first().name
        }
    }

    private fun storageRoot(context: Context): File {
        return File(context.getExternalFilesDir(null), Constants.BASE_DIR).apply { mkdirs() }
    }

    private fun containsRecordedData(userDir: File): Boolean {
        if (!userDir.exists() || !userDir.isDirectory) return false
        return (userDir.listFiles()
            ?.any { it.isDirectory && dateDirRegex.matches(it.name) && dateDirHasRecordedData(it) }) == true
    }

    private fun dateDirHasRecordedData(dateDir: File): Boolean {
        return dateDir.listFiles()?.any { file ->
            file.isFile &&
                file.name != ".uploaded" &&
                runCatching {
                    file.bufferedReader().useLines { lines ->
                        lines.drop(1).any { it.isNotBlank() }
                    }
                }.getOrDefault(false)
        } == true
    }
}
