# PD Data Collect — Project Context for Claude Code

## What This Project Is

An Android app for a Parkinson's Disease research study. It runs on participants' Galaxy S25 phones and continuously collects behavioral/sensor data in the background, then lets researchers export the data (as ZIP files) to Google Drive.

## Tech Stack

- **Language**: Kotlin
- **Min SDK**: 29 (Android 10), **Target/Compile SDK**: 35 (Android 15)
- **Build**: Gradle 8.7.3, Kotlin 1.9.22, Java 17
- **UI**: XML layouts, Material Components (no Compose, no data binding)
- **Dependencies**: AndroidX Core, AppCompat, Material, ConstraintLayout, RecyclerView, Preference

## Project Structure

```
PDDataCollect/app/src/main/java/com/pdcollect/app/
├── PDCollectApp.kt              # Application class — creates notification channels
├── data/
│   ├── DataManager.kt           # All file I/O: CSV writing, zipping, listing, deleting
│   ├── UserProfile.kt           # SharedPreferences wrapper (consent, profile, meds)
│   └── model/                   # Data classes: AppEvent, KeyEvent, SensorReading, TouchEvent
├── receiver/
│   ├── BootReceiver.kt          # Restarts services after device reboot
│   └── TMTReminderReceiver.kt   # Schedules TMT reminders at 10 AM and 4 PM
├── service/
│   ├── SensorCollectionService.kt     # Foreground service: accel/gyro/mag at max rate
│   ├── ScreenCaptureService.kt        # Foreground service: screenshots every 10s with change detection
│   ├── FaceDistanceService.kt         # Foreground service: front camera face distance every 5s
│   └── DataAccessibilityService.kt    # Captures touches, keystrokes, app switches system-wide
├── ui/
│   ├── ConsentActivity.kt       # First screen — research consent (launcher activity)
│   ├── ProfileSetupActivity.kt  # User ID, age, gender, medications
│   ├── MainActivity.kt          # Main dashboard — start/stop collection, navigate
│   ├── DataExportActivity.kt    # Lists dates, export (zip+share) or delete per date
│   ├── TrailMakingTestActivity.kt  # Cognitive test (Part A: numbers, Part B: numbers+letters)
│   └── SettingsActivity.kt      # Accessibility settings, stop services, reset consent
└── util/
    ├── Constants.kt             # All config values, file names, CSV headers, timing
    ├── NotificationHelper.kt    # Notification channel creation
    └── TimeUtils.kt             # Date/timestamp formatting helpers
```

Layouts are in `app/src/main/res/layout/` — one per activity plus `item_date_entry.xml` for the export list.

## Data Storage

All data goes to: `/sdcard/Android/data/com.pdcollect.app/files/PDCollect/{userId}/{yyyy-MM-dd}/`

Files per day:
- `sensors.csv` — accelerometer, gyroscope, magnetometer readings
- `touch.csv` — tap coordinates and scroll events
- `keys.csv` — keystroke timing (no actual text content)
- `apps.csv` — app open/close events
- `tmt_results.csv` — Trail Making Test results with full touch paths
- `face_distance.csv` — face distance proxy and facial metrics from front camera
- `screenshots/` — JPEG screenshots (50% quality, change-detection filtered)

## User Flow

1. **ConsentActivity** (launcher) → user agrees to research consent
2. **ProfileSetupActivity** → enters user ID, age, gender, medications
3. **MainActivity** → dashboard to start/stop collection, run TMT, export data
4. Background services run continuously, survive reboots via BootReceiver

## Key Data Collection Details

- **Sensors**: Buffered writes — flushes every 5 seconds or at 500 readings
- **Screenshots**: Captured every 10s at half resolution; only saved if >5% pixel difference from previous
- **Face Distance**: Uses the front camera (CameraX `ImageAnalysis`, no preview) with ML Kit Face Detection to estimate how far the phone is from the participant's face. A frame is captured every 5 seconds; ML Kit returns the face bounding box, and `distance_ratio` is computed as `face_width_px / frame_width_px` — a larger ratio means the face is closer. The service also records eye-open probabilities, smile probability, and head euler angles (Y = left/right turn, Z = tilt), which are useful for detecting PD-related reduced blinking and facial masking. Collection pauses automatically when the screen is off and resumes when it turns on. Runs as a foreground service (`LifecycleService`) with `foregroundServiceType="camera"`.
- **Accessibility Service**: Must be manually enabled by user in Android Settings; captures touches, keys, app events
- **TMT**: Deterministic layout (seed=42) so all participants see same arrangement

## Export System

`DataExportActivity` shows a RecyclerView of all date folders with size/file count. Each row has:
- **Export**: zips the date folder → shares via Google Drive (falls back to chooser if Drive not installed)
- **Delete**: confirmation dialog → recursive delete

The ZIP is created in `context.cacheDir` and shared via `FileProvider` (configured in `res/xml/file_paths.xml`).

## Build & Deploy

```bash
cd PDDataCollect
./gradlew assembleDebug          # Build
./gradlew installDebug           # Install on connected device
```

Target device: Samsung Galaxy S25 (SM-S938B) running Android 16.

## Conventions

- No Jetpack Compose — all UI is XML layouts + `findViewById`
- No dependency injection — manual construction
- Services use companion object `start()`/`stop()` pattern
- CSV headers are defined in `Constants.kt`
- Dates always formatted as `yyyy-MM-dd`, timestamps as `yyyy-MM-dd HH:mm:ss.SSS`
- `DataManager` methods are `@Synchronized` where they touch shared writers
- `ProgressDialog` is used for export (yes, it's deprecated — intentional for simplicity)

## Recent Changes

- Replaced the single "Export Yesterday's Data" button with a full **Data Export Manager** screen (`DataExportActivity`) that lists all available dates and lets the user export or delete individual dates
- Added `listAvailableDates()`, `zipDateData()`, `deleteDateData()` methods to `DataManager`
- Main button now reads "Manage & Export Data" and opens the new screen

## Known Issues / Notes

- The `TrailMakingTestActivity.kt` has local modifications (check git diff for details)
- There is no automated test suite
- The app requires the user to manually enable the Accessibility Service in system settings
- `MANAGE_EXTERNAL_STORAGE` permission is declared but the app actually uses app-specific external storage (`getExternalFilesDir`), so it may not be needed
- No ProGuard/R8 minification is enabled for release builds
