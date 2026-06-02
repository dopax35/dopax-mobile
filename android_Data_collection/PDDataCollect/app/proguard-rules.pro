# =============================================================================
# DopaX (PDDataCollect) — R8 / ProGuard rules for release builds.
# build.gradle.kts wires this in via:
#   proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"),
#                 "proguard-rules.pro")
# =============================================================================

# -----------------------------------------------------------------------------
# Strip chatty dev logging from release APKs.
#
# Why: Log.d/v/i calls scattered through services + workers (sensor sample
# rates, alarm fire timestamps, BLE state transitions, upload progress) are
# useful during development but in a release build they:
#   - leak research metadata into logcat where any other app with READ_LOGS
#     (or `adb logcat` over USB debugging) could observe it
#   - waste cycles on string concat that nobody reads
#
# We keep Log.w / Log.e / Log.wtf — those are real failure signals worth
# capturing in crash reports.
#
# -assumenosideeffects lets R8 elide each Log.* call entirely once it sees
# the return value is unused (which it always is for logging).
# -----------------------------------------------------------------------------
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
    public static *** println(...);
}

# Kotlin source line info — keep so stack traces in Crashlytics / Play Console
# remain useful after minification.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# -----------------------------------------------------------------------------
# Reflection-touched classes that R8 mustn't rename.
# -----------------------------------------------------------------------------
# WorkManager instantiates Workers reflectively by class name.
-keep class com.pdcollect.app.worker.** { *; }

# AndroidManifest references these classes by name; if R8 renames them the
# system will fail to start the component.
-keep class com.pdcollect.app.service.** { *; }
-keep class com.pdcollect.app.receiver.** { *; }
-keep class com.pdcollect.app.ui.** { *; }
-keep class com.pdcollect.app.PDCollectApp { *; }

# Kotlin coroutines internals (silence noisy R8 warnings on release builds).
-dontwarn kotlinx.coroutines.**
-keep class kotlinx.coroutines.** { *; }

# OkHttp / Okio (used by CloudUploader) — recommended consumer rules.
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# ML Kit Face Detection downloads model classes by reflection.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }
