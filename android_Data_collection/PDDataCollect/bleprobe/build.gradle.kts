plugins {
    id("com.android.application")
}

android {
    namespace = "com.pdcollect.bleprobe"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.pdcollect.bleprobe"
        minSdk = 29
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }
}
