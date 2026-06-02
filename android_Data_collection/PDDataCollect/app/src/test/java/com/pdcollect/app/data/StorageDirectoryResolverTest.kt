package com.pdcollect.app.data

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.pdcollect.app.util.Constants
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class StorageDirectoryResolverTest {

    private lateinit var context: Context
    private lateinit var profile: UserProfile
    private lateinit var storageRoot: File

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        profile = UserProfile(context)
        profile.clearAll()
        storageRoot = File(context.getExternalFilesDir(null), Constants.BASE_DIR)
        storageRoot.deleteRecursively()
        storageRoot.mkdirs()
    }

    @After
    fun tearDown() {
        profile.clearAll()
        storageRoot.deleteRecursively()
    }

    @Test
    fun resolveBaseDir_reusesSingleExistingRecordedDirectory() {
        profile.userId = "new_user"
        val existingDir = File(storageRoot, "existing_user/2026-05-17").apply { mkdirs() }
        File(existingDir, Constants.SENSORS_FILE).writeText(
            Constants.SENSORS_HEADER + "\n1,0,0,0,0,0,0,0,0,0"
        )

        val resolved = StorageDirectoryResolver.resolveBaseDir(context, profile)

        assertEquals("existing_user", profile.userId)
        assertEquals(File(storageRoot, "existing_user").absolutePath, resolved.absolutePath)
    }

    @Test
    fun migrateUserDirectory_movesExistingRecordedDaysToNewUserId() {
        val oldDateDir = File(storageRoot, "old_user/2026-05-17").apply { mkdirs() }
        val sensorFile = File(oldDateDir, Constants.SENSORS_FILE)
        val content = Constants.SENSORS_HEADER + "\n1,0,0,0,0,0,0,0,0,0"
        sensorFile.writeText(content)

        StorageDirectoryResolver.migrateUserDirectory(context, "old_user", "new_user")

        assertFalse(File(storageRoot, "old_user").exists())
        val migratedFile = File(storageRoot, "new_user/2026-05-17/${Constants.SENSORS_FILE}")
        assertTrue(migratedFile.exists())
        assertEquals(content, migratedFile.readText())
    }
}
