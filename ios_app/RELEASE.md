# DopaX iOS Release Notes

---

## 3.7.38 (build 126) — 2026-08-07

### Active Tests Suite Integration & UI Redesign

- **Integrated `face_test`, `fingers_test`, `voice_test` repositories**:
  - Added 5-step guided **Facial Movement Test** (`FacialMovementTestView.swift`) measuring resting hypomimia, smile amplitude, eyebrow elevation, mouth pucker, and rapid blink frequency.
  - Enhanced **Finger Tapping** with hand-size normalized tapping analytics and pinch interval metrics.
  - Enhanced **Voice Recording** with sustained `/a/` phonation and speech dynamics quality tracking.
- **Active Tests Redesign**: Reorganized the Active Tests view into 4 distinct categories:
  1. 🧠 **Cognitive & Executive**: Trail Making Test A & B
  2. 🗣️ **Voice & Speech Dynamics**: Voice Sample Recording
  3. 🖐️ **Motor & Movement**: Finger Tapping, Hand Turning, Spiral Tracing, Leg Agility
  4. 😊 **Facial Expressions**: Facial Movement Test
- **Dedicated Mac Build Scripts**:
  - `build_mac_sensorkit.sh`: Archive and export `.ipa` with full SensorKit entitlements.
  - `build_mac_nosensorkit.sh`: Archive and export `.ipa` for TestFlight / standard App Store signing without SensorKit.

---

## 3.8.0 (build 122) — 2026-07-30

### Apple SensorKit Reader Access Integration & Ad-Hoc Downloadable Build

- **SensorKit Reader Entitlements Added**: Added entitlement `com.apple.developer.sensorkit.reader.allow` for approved data streams: `accelerometer`, `rotation-rate`, `keyboard-metrics`, `device-usage` under Apple Case-ID: `20926388`.
- **SensorKit Manager (`SensorKitManager.swift`)**: Added native `SRSensorReader` orchestration for authorization, periodic fetch cycles, and logging into research CSV files:
  - `sensorkit_accelerometer.csv`
  - `sensorkit_rotation_rate.csv`
  - `sensorkit_keyboard_metrics.csv`
  - `sensorkit_device_usage.csv`
- **Background & Active Fetch**: Wired SensorKit data fetching into app foreground activation and background processing tasks (`com.pdcollect.ios.bg-processing`).
- **Settings UI**: Added **SensorKit Reader Access** section in Settings with live authorization badges, authorization request trigger, and manual fetch options.
- **Downloadable Ad-Hoc IPA Script**: Added `build_adhoc_ipa.sh` for compiling an Ad-Hoc downloadable `.ipa` installer package for direct deployment to registered devices prior to TestFlight approval.

---

## 3.7.30 (build 116) — 2026-07-28

### Stability hardening + Beanie/HR BLE reliability (full-codebase review)

- **Keyboard extension App Group entitlement added** — the extension's
  entitlements file was empty, so `containerURL(forSecurityApplicationGroup:)`
  returned nil and every keystroke-metrics write silently no-op'd. Typing
  metrics collection works for the first time in this build. (Regenerate the
  Xcode project with `./setup.sh` so the entitlement is picked up.)
- HR strap reconnect no longer gives up after 5 attempts — added the same
  indefinite scan-based fallback the Beanie already had.
- Beanie data watchdog dead-end fixed: when live-start retries exhaust and
  read-polling isn't available, it now keeps retrying at reduced cadence
  instead of leaving the device "connected" but silent.
- CoreBluetooth state restoration now reattaches the Beanie peripheral
  (previously only HR), closing a background-relaunch data gap.
- ARKit face tracking: distance now measured from the live camera position
  (was drifting from the fixed world origin); session auto-recovers after
  interruptions (calls, thermal, camera contention).
- Thread-safety: passive sensor (50Hz) and motor-test (100Hz) buffers are
  now serialized on their delivery queues (data-race crash risk).
- BGTask handlers can no longer double-complete (API misuse that risks
  background-scheduling throttling).
- Settings "Data Collection" off now also stops HR/Beanie BLE writes.
- Deleting a day's data is serialized against in-flight writes; today's
  active folder can't be deleted mid-collection.
- Gaze/face CSV values guard against NaN/Inf corrupting downstream parsing.
- New: gaze tracking (`gaze_tracking.csv`) via ARKit TrueDepth with Vision
  fallback — new file `Models/GazeSample.swift` (picked up by XcodeGen).

---

## 3.7.29 (build 115) — 2026-07-18

### Fix: User profile erasure on app update

Root cause: The Firebase authentication gate introduced in v3.7.x requires users
to sign in. After an app update, Firebase sessions often expire, forcing re-auth.
If no Firestore document existed for the user's account (all pre-auth users), the
app silently blanked their profile and assigned a new random participant ID.

**Changes:**

- **`UserProfile`** — `userId` is now backed by the iOS Keychain (scoped to
  bundle ID + `"participantUserId"`) in addition to UserDefaults. Resolution
  order on init: UserDefaults → Keychain (survives reinstall) → generate new.
  Keychain writes use update-then-add to avoid race conditions.
- **`UserProfile.mergeFromCloud()`** — new local-wins merge. When called on
  sign-in, only fills in fields that are blank locally *and* only if the profile
  is not yet marked complete. Once complete, all local values are trusted
  absolutely and never overwritten by the cloud.
- **`FirebaseSyncManager.syncProfileOnSignIn()`** — new smart sign-in sync:
  if a Firestore document exists for the Firebase UID it merges (local wins);
  if no document exists it immediately uploads the local profile to cloud,
  preserving the participant's original `userId` and all their data.
  Completion is always called even if self is deallocated mid-request.
- **`LoginView`** — uses `syncProfileOnSignIn` instead of `loadProfileFromCloud`
  (which was a destructive full-overwrite). Added **"Continue without signing in"**
  escape hatch so existing users who update are never blocked from their data.
  Cancelling the sign-in sheet no longer shows an error.
- **`AppState`** — `skipSignIn()` / `clearSkipSignIn()` persist the skip
  decision across app restarts via `"hasSkippedLogin"` in UserDefaults.
- **`ContentView`** — auth gate now checks `currentUser != nil || hasSkippedLogin`.
  Added smooth animation for auth state transitions.
- **`SettingsView`** — **Sign Out** now only drops the Firebase session and clears
  `hasSkippedLogin`; it no longer calls `clearAll()`. Local profile data is
  fully preserved on sign-out. `clearAll()` is only reachable from
  **"Reset Consent & Start Over"**.

---


## What's in 3.7.13 (build 97)

One targeted fix, made while investigating and hardening the Android
regression described in `PD_App_Review_and_Fixes.md` (round 16) and
verifying the same class of bug didn't also exist on iOS:

- `HealthKitManager.fetchGaitMetrics`: removed a force-unwrap
  (`Calendar.date(byAdding:)!`) that could, in principle, trap the whole
  process if the Calendar call ever returned `nil` — this runs inside the
  same background-task chain as `PedometerHistoryService` /
  `MotionActivityHistoryService`, so a trap here would have taken those
  down too for that wake. Now falls back to a safe date computation
  instead of force-unwrapping.

Everything else added in the last few rounds (`PedometerHistoryService`,
`MotionActivityHistoryService`, Wi-Fi-aware auto-upload, the pedometer
timestamp-clustering and window-duplication fixes) is unchanged by this
release; see `PD_App_Review_and_Fixes.md` rounds 12-15 for that history.

---

## ⚠️ Before you touch this project: `project.yml` is stale — do not run `xcodegen generate`

This project was originally scaffolded with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml` at the
repo root generates `PDCollectiOS.xcodeproj/project.pbxproj`). At some
point the team switched to editing `project.pbxproj` directly in Xcode
instead, and `project.yml` was never kept in sync. As of this release:

- `project.yml` still says `MARKETING_VERSION: 3.7.21` /
  `CURRENT_PROJECT_VERSION: 109` — both **wrong** (currently 3.7.13 / 97
  in the real project) and, more importantly, it has no entries at all
  for every file added since the drift started, including
  `PedometerHistoryService.swift`, `MotionActivityHistoryService.swift`,
  `PedometerSample.swift`, `MotionActivitySample.swift`, `StravaManager.swift`,
  and others.
- **If anyone runs `xcodegen generate` against the current `project.yml`,
  it will regenerate `project.pbxproj` and silently drop every one of
  those files from the build** — the exact "file exists on disk but
  isn't compiled" bug already found and fixed once this engagement
  (`StravaManager.swift`, round 12). It would not show up as a build
  error; the missing features would just quietly stop working.
- Until someone reconciles `project.yml` with the real project (or the
  team formally commits to editing `project.pbxproj` by hand going
  forward and deletes `project.yml` to remove the trap), treat
  `project.yml` as historical and do not regenerate from it.

## 1. One-time setup

- [ ] **macOS + Xcode** (15.x or newer for iOS 16 deployment target /
      Swift 5.9 — check `project.pbxproj`'s `IPHONEOS_DEPLOYMENT_TARGET`
      and `SWIFT_VERSION` if Xcode complains).
- [ ] **Apple Developer Program membership**, team ID `YD2UPLT5JG`
      (already referenced in `project.pbxproj`'s `DEVELOPMENT_TEAM`).
- [ ] Confirm your Xcode account has access to team `YD2UPLT5JG` and
      that automatic signing (`CODE_SIGN_STYLE = Automatic`) can
      provision both targets: `PDCollectiOS` (bundle id
      `com.oriw.pdcollect.ios1`) and the `PDCollectKeyboard` keyboard
      extension target.
- [ ] HealthKit, BGTaskScheduler (`com.pdcollect.ios.bg-refresh` /
      `com.pdcollect.ios.bg-processing`), and any other capabilities
      declared in `PDCollectiOS.entitlements` must be enabled on the
      App ID in the Apple Developer portal, or Archive will fail
      signing with a capability-mismatch error.

## 2. Pre-flight on the source

- [ ] `git status` is clean. Anything uncommitted goes in or gets
      reverted before archiving. (As of this round, everything from
      this multi-session engagement was still uncommitted working-tree
      state — confirm with the team what should actually ship before
      assuming the working tree is release-ready.)
- [ ] Open `PDCollectiOS.xcodeproj` directly in Xcode — do **not** run
      `xcodegen generate` first (see warning above).
- [ ] Confirm the version: Xcode → target `PDCollectiOS` → General →
      should read Version `3.7.13`, Build `97`.

## 3. Build the archive

No `fastlane`/CI script exists for iOS yet (unlike Android's
`build-aab.ps1`) — this is a manual Xcode Organizer flow:

1. Xcode → select the `PDCollectiOS` scheme → Any iOS Device (arm64) →
   **Product → Archive**.
2. Once archived, Xcode Organizer opens automatically. Validate the
   archive first (**Validate App**) before distributing — this catches
   signing/capability issues without spending a TestFlight upload.
3. **Distribute App → TestFlight (Internal Testing)** → follow the
   signing prompts (automatic signing should just work if step 1's
   team access is correct).

## 4. Smoke-test before wide distribution

- [ ] Fresh install → grant Motion & Fitness, HealthKit, Notifications
      permissions when prompted → confirm the dashboard loads.
- [ ] **New for this release**: background the app and reopen it
      5-10 times in a row. Each time, confirm the dashboard still
      renders and nothing looks stuck — this release didn't change
      iOS's onResume-equivalent logic (the bug fixed this round was
      Android-only), but it's the same regression class, so it's worth
      confirming iOS truly has no equivalent issue in practice, not
      just on paper.
- [ ] Run one active test (e.g. Finger Tapping) and confirm its CSV
      appears via Settings → Data / Debug preview.
- [ ] Check Settings → enable the PDCollect Keyboard, confirm
      `key_events.csv` gets rows when typing in the keyboard's own
      trigger field.
- [ ] If a crash happens during testing, confirm it surfaces the way
      you'd expect from Xcode Organizer → Crashes, and cross-check
      against `PD_App_Review_and_Fixes.md` if the signature looks like
      the concurrent-deallocation crash logged earlier this engagement
      (Jul 7 2026, iPhone 15 Plus) — that one is still only diagnosed
      down to its signature, not its exact cause; a fuller stack trace
      from Organizer is still needed if it recurs.

## 5. Post-release

- [ ] Tag the release in git: `git tag v3.7.13-ios -m "DopaX iOS 3.7.13 (build 97)"`
      and push the tag. (Suffixed `-ios` since Android's version numbers
      have drifted independently — 3.7.25 on Android vs 3.7.13 on iOS at
      this same point in time. That's expected given how platform-specific
      most fixes have been; it isn't a bug, just worth knowing when
      comparing build numbers across platforms.)
- [ ] Archive the `.xcarchive` outside the repo (Xcode Organizer →
      right-click → Show in Finder) — needed to re-symbolicate any
      future crash report against this exact build.
