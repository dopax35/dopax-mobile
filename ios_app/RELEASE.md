# DopaX iOS 3.7.13 (build 97) - release checklist

There was no equivalent of the Android project's `RELEASE.md` for iOS
before this round — this is a first pass modeled on it. Tick items as
you go.

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
