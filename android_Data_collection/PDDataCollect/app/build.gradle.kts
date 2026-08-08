import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
}

val keystorePropertiesFile = file("keystore.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val releaseSigningConfigured = listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all { key ->
    !keystoreProperties.getProperty(key).isNullOrBlank()
}
val releaseTaskRequested = gradle.startParameter.taskNames.any { taskName ->
    taskName.contains("release", ignoreCase = true) ||
        taskName.contains("bundle", ignoreCase = true) ||
        taskName.contains("publish", ignoreCase = true)
}
if (releaseTaskRequested && !releaseSigningConfigured) {
    throw GradleException(
        "Missing app/keystore.properties with storeFile, storePassword, keyAlias, and keyPassword."
    )
}

android {
    namespace = "com.pdcollect.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.pdcollect.app"
        minSdk = 29
        targetSdk = 35
        // Bumped from 40 / "3.0.2" for the May 2026 screen-distance update:
        // - Feat: 20 Hz face-distance sampling (was 0.2 Hz)
        // - Feat: Distance measurement gated on screen-on AND foreground app
        // - Fix: Correct idle-package detection (exact match + sub-package)
        // - Build: NDK debugSymbolLevel moved to release buildType; uncompressed JNI packaging
        // Note: vc41 was consumed by an earlier Play Console upload; using vc42.
        // v3.3.1 (vc 53): Beanie Connection & Graph Scaling fix.
        // - Fix: Prevented GATT connection leaks in BeanieService via explicit cleanup.
        // - Fix: Hardened graph scaling to ignore absurdly high outlier values.
        // - Perf: Added ScanFilter for Beanie service UUID to improve BLE battery efficiency.
        // v3.4.5 (vc 67): PDAnalysis dashboard graphs.
        // - Fix: Dashboard gait graphs now use the PDAnalysis walking classifier and step model.
        // - Fix: Graph cache version bumped so phones rebuild stale/empty summaries.
        // v3.4.6 (vc 68): Stable dashboard and Beanie reconnect.
        // - Fix: Fast dashboard sync skips huge uncached historical sensor files to avoid memory blowups.
        // - Fix: Beanie vitals keep the last valid temperature visible while the service reconnects.
        // - Fix: Beanie reconnect uses low-latency scan and auto-connect fallback for saved devices.
        // v3.4.8 (vc 70): Offline dashboard graph cache and buffered Beanie IMU parsing.
        // - Fix: Dashboard presents cached graph data while WorkManager analyzes raw files in background.
        // - Fix: Graph cache version bumped again so phones rebuild any stale/empty summaries.
        // - Fix: Stable tremor filtering prevents NaN/empty tremor graphs on 25 Hz phone traces.
        // - Fix: Beanie IMU packets split across BLE notifications are buffered before parsing.
        // v3.4.9 (vc 71): Idempotent upload and live dashboard/Beanie recovery.
        // - Fix: Prevent duplicate Drive files by locking each date upload and treating streamed upload as complete.
        // - Fix: Skip header-only dates and upload marker files during backup.
        // - Fix: Refresh dashboard graphs immediately from local summaries when the home screen opens.
        // - Fix: Do not display stale Beanie temperatures as live readings.
        // v3.4.13 (vc 75): Passive collection onboarding and medication setup recovery.
        // - Fix: New participants now finish setup with passive collection enabled by default.
        // - Fix: Profile setup no longer misclassifies fresh installs as an existing profile.
        // - Fix: Medication editing is available again from Settings and saved back into the profile snapshot.
        // v3.4.4 (vc 66): Beanie command-stream startup.
        // - Fix: Start Beanie live recording through the firmware command characteristic.
        // - Fix: Parse newer 247-byte Beanie IMU stream packets without false temp rows.
        // v3.4.3 (vc 65): Fast Graph Recovery & Beanie Rediscovery.
        // - Fix: Fast dashboard sync now skips header-only days and scans recent real data.
        // - Fix: Beanie monitor rediscovery no longer depends on service-UUID advertisements.
        // v3.4.2 (vc 64): Dashboard Recovery & Beanie Fallbacks.
        // - Fix: Reset dashboard cache version and force raw-summary rebuild when startup stays empty.
        // - Fix: Recover passive gait summaries after long idle gaps in real sensor traces.
        // - Fix: Add Beanie read-poll fallback when Android notification registration breaks.
        // v3.4.14 (vc 77): Multi-day daily charts, fullscreen zoom, and safer release signing.
        // - Feat: Daily dashboard charts now compare today with the previous two days using moving averages.
        // - Feat: Tapping any dashboard chart opens a fullscreen landscape view with pinch-zoom and pan.
        // - Sec: Release signing secrets now load from local-only app/keystore.properties instead of tracked Gradle code.
        // v3.4.15 (vc 78): Graph usability polish and storage-permission hardening.
        // - Fix: Fullscreen chart detail now exposes an explicit back button in landscape.
        // - Fix: Daily dashboard charts label recent days more clearly and show medication times on the traces.
        // - Sec: Removed legacy external storage flags because the app only uses app-specific external files.
        // v3.4.16 (vc 79): Daily graph timeline correctness and release verification.
        // - Fix: Today daily charts now stop at the current time instead of rendering a full-day future trace.
        // - Fix: Previous-day traces and medication markers are clearly dashed while today remains solid blue.
        // - Build: Release path is verified with lint, unit tests, and AAB bundling before shipping.
        // v3.4.17 (vc 80): Hand-turning spoken cues and lifecycle hardening.
        // - Feat: Pronation-supination test now announces get-ready, start, and stop cues with beep fallback.
        // - Fix: Hand-turning countdown and speech resources are cancelled cleanly across activity teardown.
        // - Build: Release path is re-verified with lint, unit tests, and signed AAB bundling.
        // v3.4.18 (vc 81): Motor-test cue alignment and Samsung stability verification.
        // - Fix: Leg Agility now uses the same get-ready, start, and stop audio cue flow as Hand Turning.
        // - Fix: Hand Turning remains orientation-locked during pronation-supination to avoid Samsung auto-rotate teardown.
        // - Build: Release security checks, lint, unit tests, and signed AAB bundling were re-verified for internal testing.
        // v3.4.20 (vc 83): Resolve Pixel 9 crash and Android 14+ background startup issues.
        // - Fix: Use ResolutionSelector with fallback to prevent CameraX crashes on devices with strict resolution limitations.
        // - Fix: Split background sensor collection (specialUse) from dynamic camera collection (camera) to avoid background FGS startup restrictions on Android 14+.
        // v3.5.0 (vc 84): Firebase auth, E-Consent, Walkthrough and test nudges.
        // - Feat: Users can now authenticate with Firebase (Email, Phone, Google, Apple) and data syncs across reinstallations.
        // - Feat: Electronic signature integration with PDF study agreement using Android PdfRenderer.
        // - Feat: First-time user walkthrough overlay implemented on the dashboard.
        // - Feat: Encouragement messages / positive reinforcement dynamically shown after active motor tests.
        // v3.6.0 (vc 85): Configured Google-Services JSON for Firebase Auth.
        // - Build: Updated google-services.json SHA-1 hashes and verified Firebase Auth flow.
        // v3.7.1 (vc 87): Firestore Sync Fixes
        // - Feat: Added email, signature, and graph metrics to Firebase uploads.
        // v3.7.25 (vc 111): Fixed most-CSV-files-missing regression.
        // - Fix: MainActivity.onResume() ran 5 independent steps (service sync,
        //   dashboard charts, setup-health check, reminders, profile write) as one
        //   unguarded sequence — a failure in any one silently skipped the rest,
        //   including the profile.csv write, on every future app open. Each step
        //   now runs in isolation.
        // - Fix: crash logs (crash_logs/) are now bundled into the daily export
        //   zip, so a crash loop like this is visible remotely next time.
        // - Fix: same onResume isolation applied to SettingsActivity.
        // - Fix: zip export no longer aborts entirely if one file/log is unreadable.
        // v3.7.27 (vc 113): CSV pre-creation, Beanie BLE fixes, and custom guides.
        // - Fix: Pre-create all daily CSV files (passive & active) on startup.
        // - Fix: Hardened Beanie GATT connect/autoConnect flow and added 600ms delay.
        // - Fix: End-of-battery questionnaire logic and new custom guide images.
        // v3.7.27 (vc 113): Duplicate-upload prevention, recursive iOS size display, Android upload on launch, face-distance fallback.
        // - Fix: iOS now uses an .uploading claim-file lock (mirrors Android UploadState) so concurrent
        //   BGProcessingTask wakeups and manual upload taps cannot race and send the same date twice.
        // - Fix: iOS sizeString() and fileCount() are now recursive, so voice/ subdirectory recordings
        //   are counted correctly in the export view.
        // - Fix: Android fires an immediate DataUploadWorker.enqueueOneTimeUploads() on every app launch
        //   so data is not stuck waiting for the 02:00 periodic dispatcher.
        // - Fix: FaceDistanceService.startRecorderIfNeeded() now logs the reason for every early-return;
        //   adds a 10 s screen-on fallback so ALWAYS mode records even when Accessibility Service is
        //   not enabled; stamps SharedPreferences with lastFaceDistanceSampleMs for UI diagnostics.
        // v3.7.28 (vc 114): Version bump and release prep — expert review verified, changelogs backfilled.
        // v3.7.30 (vc 116): Stability hardening (writer rotation, FGS permission guards, delete-today
        // guard) + Beanie BLE reliability: autoConnect passthrough, live-stream stall watchdog,
        // shape-based packet filtering (fixes garbage temp rows + silent recording stalls).
        // v3.7.31 (vc 117): Beanie NVS storage management — erase hat flash at 5% usage
        // (reference-app parity); fixes the connect → stream 10-30s → disconnect loop caused by
        // never-erased NVS destabilizing the firmware.
        // v3.7.32 (vc 118): ROOT CAUSE of the Beanie disconnect loop — PDCollect seeded the
        // RTC (0xA4/SET_TIME/0x04) on every connect, which both reference implementations
        // explicitly forbid ("RTC is NEVER seeded here"). Ported their connection scheme:
        // subscribe-only connect, 2M PHY, immediate MTU, single last-resort live-start.
        // v3.7.33 (vc 119): Beanie packet parsing/ML inference moved OFF the GATT callback
        // (Binder) thread onto a dedicated HandlerThread — reference architecture parity
        // (BleViewModel: callback only does incoming.trySend, a background consumer parses).
        // Blocking the callback thread starved the BLE stack -> supervision timeout ->
        // connect-then-drop after 10-30s with temps/flux frozen. Also restores the
        // post-connect settle delay and the fast direct-connect path.
        // v3.7.34 (vc 120): stop the stall watchdog force-disconnecting a live link (it turned
        // any stream pause into the connect/disconnect loop); recover in place instead. Allow
        // re-export of already-uploaded dates. Add BeanieService HEALTH diagnostics.
        // v3.7.35 (vc 121): ROOT CAUSE of the Beanie connect/disconnect loop — the GATT
        // state machine was multi-threaded. bluetoothGatt was written on the main thread
        // AND the scan binder thread, and read on the BLE binder thread with no
        // synchronisation; ignoreStaleGattCallback() closes whatever it judges stale, so a
        // stale read closed the live connection. All GATT/scan callbacks are now pinned to
        // v3.7.40 (vc 128): Camera tests (face_test, fingers_test) with live Vision/ARKit landmark overlays,
        // positioning guidance banners, and SensorKit launch crash / ITMS-90683 resolution.
        versionCode = 128
        versionName = "3.7.40"
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
            // R8 shrinking + obfuscation. Crash stack traces are still mappable via the
            // generated mapping.txt — keep that file with the build artifacts.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Embed unstripped .so files in the AAB so Google Play (and
            // extractReleaseNativeDebugMetadata) can extract crash symbols.
            // Must be in the buildType block (not defaultConfig) to take effect
            // for dependency-provided native libs (ML Kit, CameraX, etc.).
            ndk {
                debugSymbolLevel = "FULL"
            }
        }
    }

    // BuildConfig.DEBUG is used to gate the hidden debug-data-preview corner
    // trigger on the dashboard (see MainActivity) so it's inert in release/
    // participant-facing builds. AGP 8+ no longer generates BuildConfig by
    // default, so this must be opted into explicitly.
    buildFeatures {
        buildConfig = true
    }

    // Store .so files uncompressed in the AAB — required for Play to process
    // embedded native debug symbols and for faster app installs on Android 6+.
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.preference:preference-ktx:1.2.1")
    implementation("androidx.recyclerview:recyclerview:1.3.2")

    // CameraX
    implementation("androidx.camera:camera-core:1.3.0")
    implementation("androidx.camera:camera-camera2:1.3.0")
    implementation("androidx.camera:camera-lifecycle:1.3.0")

    // ML Kit Face Detection
    implementation("com.google.mlkit:face-detection:16.1.5")

    // LifecycleService (needed for CameraX binding in a service)
    implementation("androidx.lifecycle:lifecycle-service:2.7.0")

    // Automated Sync & Cloud Upload
    implementation("androidx.work:work-runtime-ktx:2.9.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Firebase
    implementation(platform("com.google.firebase:firebase-bom:33.1.2"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.firebaseui:firebase-ui-auth:8.0.2")

    // Mandatory In-app Updates
    implementation("com.google.android.play:app-update-ktx:2.1.0")

    // TensorFlow Lite
    implementation("org.tensorflow:tensorflow-lite:2.16.1")
    implementation("org.tensorflow:tensorflow-lite-support:0.4.4")

    // Health Connect
    implementation("androidx.health.connect:connect-client:1.1.0-alpha07")

    // LocalBroadcastManager — used for intra-process service communication
    // (DataAccessibilityService → FaceDistanceService foreground-app events)
    implementation("androidx.localbroadcastmanager:localbroadcastmanager:1.1.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.11.1")
    testImplementation("androidx.test:core:1.5.0")
}
