# DopaX 3.7.31 (versionCode 117) - release checklist

End-to-end "from clean checkout to AAB uploaded to Play Console
Internal Testing" steps. Tick items as you go.

---

## What's in 3.7.31 (vc 117)

Fixes the remaining Beanie failure mode after vc 116: the hat still
dropped the connection 10-30s after every connect. Root cause (found by
protocol comparison with the reference lukasIFM/BeanieAppAndroid app):
the hat logs history into its internal NVS flash, every RTC seed we send
on connect writes a START marker into that flash, and the reference app
*erases the flash whenever usage reaches 5%* during live streaming —
this app never erased it at all. Months of accumulation left the
firmware sitting on full/degraded flash, destabilizing it shortly after
each connect.

Changes (BeanieService.kt):
- Storage notifications (0xA1) are now parsed instead of discarded; at
  >= 5% usage the app sends ERASE_ALL (0x03), matching the reference
  app's live auto-erase.
- The firmware drops BLE during the ~90s erase — this is now an
  *expected* disconnect: no failure heuristics fire, the stall watchdog
  and warmup RTC retries are suppressed for the window, and the normal
  on-connect RTC seed doubles as the post-erase re-seed.
- Safety valves: no erase in the first 5s of a connection, max one
  erase per hour (protects the flash from erase loops on misreads).

**Smoke-test for this release**: pair the hat and record. On first
connect with a full hat, expect the notification to show
"Beanie storage N% - erasing (approx. 90s)...", one disconnect, then an
automatic reconnect followed by *stable* 5s-cadence rows in
`beanie_temperature.csv` for 30+ minutes. Subsequent connects should
show storage < 5% and no erase.

---

## What's in 3.7.30 (vc 116)

Beanie BLE reliability + general stability hardening (full-codebase review).

Beanie fixes (root causes found by comparing against the reference
lukasIFM/BeanieAppAndroid implementation — see BeanieService.kt comments):
- `connectGatt` autoConnect flag is now actually passed through (was
  hardcoded `false`), so reconnects are OS-level background retries
  instead of one-shot ~30s attempts that race-fail when the hat is
  briefly out of range. This was the main "keeps disconnecting" cause.
- New live-stream stall watchdog: if a "connected" hat delivers no
  temp/IMU frame for 30s (or never streams within 60s), the service
  forces a full disconnect/reconnect cycle. Previously a silently
  stalled stream left the service in READY forever, recording nothing.
- Shape-based packet filtering (reference-app parity): unknown packet
  types (storage notifies, command echoes, barcode chunks) are consumed
  instead of byte-scanned, which was producing a constant garbage
  temperature row (87.62 C) beside every real sample and phantom
  battery readings.

General stability (same review):
- DataManager: all CSV writes serialized onto the I/O thread — fixes a
  daily midnight writer-rotation race that could crash or drop rows.
- Foreground services (FaceDistance/AntHR/Beanie) no longer crash-loop
  if Camera/Bluetooth permission was revoked between restarts.
- Deleting *today's* data folder is now blocked while collection is live.
- Motor-test activities no longer crash if backed out during the
  post-test 1.5s transition window.
- Setup health check now also monitors Usage-Stats + overlay permission
  (Android can silently revoke both).
- Firestore dashboard sync bounded to 90 days (1 MiB doc-cap guard).

**Extra smoke-test step for this release**: pair the Beanie hat, record
~1 hour including deliberately walking out of BLE range for 2-3 minutes
and returning. Then check the day's `beanie_temperature.csv`: expect
continuous ~5s cadence, no `87.62` rows, and automatic resumption after
the out-of-range gap.

---

## What's in 3.7.28 (vc 114)

Fixes a regression where most CSV files (active-test results, medication,
physical activity, profile, voice log, sleep, questionnaire, heart rate,
Beanie temperature/IMU) stopped being written for some participants,
while `apps.csv`/`key_events.csv`/`sensors.csv`/`touch_events.csv` — written
by independent background services rather than `MainActivity` — kept
working. Root cause: `MainActivity.onResume()` ran five independent steps
(service sync, dashboard chart rendering, setup-health check, reminder
scheduling, profile write) as one unguarded sequence; an exception in any
one step silently skipped every step after it, including the profile
write, on every single future app open. See
`PD_App_Review_and_Fixes.md`, round 16, for the full investigation.

Changes in this build:
- `MainActivity.onResume()` and `SettingsActivity.onResume()`: each step
  now runs independently, so one failing step can no longer block the rest.
- Crash logs (`crash_logs/`) are now bundled into the daily export zip —
  previously invisible in every export, so a crash loop like this one had
  no way to be diagnosed without physically pulling the file off the
  device. Check the next few participants' exports for a `crash_logs/`
  folder — if one turns up, that's the smoking gun for the exact
  exception, which the round-16 investigation could not pin down without
  it.
- The zip export itself is now resilient to one bad/unreadable file — it
  used to abort the whole day's export if any single file failed to read.
- One iOS-side hardening in the same spirit (force-unwrap removed from
  `HealthKitManager.fetchGaitMetrics`) — see the iOS release notes.

**Extra smoke-test step for this release** (in addition to section 4
below): background the app and reopen it 5-10 times in a row. Each time,
confirm the dashboard still updates and `profile.csv` gets a new row
(Settings → "View Recent Data", or the debug data preview screen).

---

## 1. One-time setup (skip if your laptop already has it)

- [ ] **JDK 17** installed and `JAVA_HOME` pointing at it.
      The `jdk17/` folder bundled in this repo is for reference; on
      Windows you should install a real JDK 17 via Adoptium / Temurin.
- [ ] **Android SDK** with platform-35 + build-tools-35 + Android
      SDK Command-line Tools. Easiest path: install Android Studio,
      open SDK Manager, accept those packages. Then put the SDK path
      into `local.properties`:
      ```
      sdk.dir=C\:\\Users\\you\\AppData\\Local\\Android\\Sdk
      ```
- [ ] **Play Console developer account** ($25 one-time).
- [ ] **App registered** in Play Console with package name
      `com.pdcollect.app`.

## 2. Pre-flight on the source

- [ ] `git status` is clean. Anything uncommitted goes in or gets
      reverted before tagging the release.
- [ ] **Rotate the keystore credentials.** A previous commit
      (`feeb5a8`, March 25 2026) contained `my-password` and
      `my-key-alias` in plaintext. Even after the patch that moved
      these to `keystore.properties`, the *historical* credentials are
      still in your git log. Either:
      - Best: generate a NEW keystore + key, update Play App Signing
        with the new upload key, and rewrite git history with
        `git filter-repo` to scrub the old strings; or
      - Acceptable for a private pilot repo: change the keystore
        password and key password to new values not in the history.
- [ ] **Confirm `app/keystore.properties` is local-only** (`git ls-files |
      grep keystore.properties` should be empty). Confirm
      `my-release-key.jks` is also local-only.
- [ ] **Confirm `testers.csv` is not committed** — it contains
      participant emails.

## 3. Build the AAB

```powershell
cd path\to\PDDataCollect
.\build-aab.ps1
```

This script: cleans, runs lint, runs unit tests, and bundles the
release. It refuses to continue if `app/keystore.properties` is
missing.

When it finishes you should see:
```
================================================================
  AAB built successfully
  Path:    .\app\build\outputs\bundle\release\app-release.aab
  Size:    ~25 MB
  Mapping: .\app\build\outputs\mapping\release\mapping.txt
================================================================
```

## 4. Smoke-test the AAB locally (optional but recommended)

If you have `bundletool` installed, you can install the AAB on a
connected test device the same way Play would:

```powershell
bundletool build-apks --bundle=app\build\outputs\bundle\release\app-release.aab `
                       --output=app\build\outputs\bundle\release\app-release.apks `
                       --connected-device --ks=app\my-release-key.jks `
                       --ks-key-alias=YOUR_ALIAS
bundletool install-apks --apks=app\build\outputs\bundle\release\app-release.apks
```

Walk through these on the device:
- [ ] Fresh install → Consent → Profile Setup. The new "Body side"
      card should appear between Basic Identity and Medications,
      showing Dominant Hand + Side More Affected by PD radio groups.
- [ ] Run a Spiral test. Open the resulting `spiral_tracing.csv`
      (Settings → View Recent Data). Confirm:
      - First row is `event=START`, `elapsed_ms=0`, x/y/action blank.
      - Then `event=SAMPLE` rows.
      - Final row is `event=END`.
      - Every row has the dominant_hand and affected_side you set.
- [ ] Settings → Body side → change the affected-side answer. Run
      another test. Confirm the new value lands in the next test's
      CSV.
- [ ] Settings → "Withdraw from study" → confirm dialog → confirm
      everything is wiped: storage path is empty, prefs are reset,
      app reopens to Consent screen.

## 5. Upload to Play Console (Internal Testing track)

- [ ] Play Console → DopaX app → Testing → Internal testing →
      Create new release.
- [ ] Upload `app-release.aab`.
- [ ] Upload `mapping.txt` in the same dialog (under "App bundles /
      mapping file"). Future crash stacks de-obfuscate automatically.
- [ ] Paste the contents of
      `fastlane/metadata/android/en-US/changelogs/114.txt` into the
      "Release notes" box.

## 6. Fill in the Console listing fields

These are one-time per app, but the Console will keep nagging until
they are all green-ticked.

- [ ] **App content → Privacy policy** → paste the public HTTPS URL
      where you've hosted `privacy_policy.html`. (If you do not yet
      have one hosted, GitHub Pages on a private repo backed by a
      university email is the fastest path.)
- [ ] **App content → Data safety** → answer using
      `fastlane/metadata/android/play-console/data-safety.md`.
- [ ] **App content → Content rating** → run the IARC questionnaire
      using `fastlane/metadata/android/play-console/content-rating.md`.
- [ ] **App content → Target audience and content** → 18+, "No, my
      app is not appealing to children".
- [ ] **App content → Permissions declaration form** —
      Console will prompt for `BIND_ACCESSIBILITY_SERVICE`,
      `SCHEDULE_EXACT_ALARM`, `PACKAGE_USAGE_STATS`,
      `SYSTEM_ALERT_WINDOW`, `FOREGROUND_SERVICE_SPECIAL_USE`. Paste
      the per-permission justifications from `data-safety.md`.
- [ ] **Store listing → App icon, feature graphic, screenshots** —
      see specs in `play-console/store-listing-checklist.md`. Internal
      Testing track does NOT require these to roll out, but Play will
      complain on the dashboard until they are filled in.
- [ ] **Store settings → App category** → Medical.

## 7. Add testers and roll out

- [ ] Internal testing → Testers tab → create or pick a tester list →
      paste the participant emails from `testers.csv`. (Reminder: do
      not commit `testers.csv` back into git.)
- [ ] Save the **opt-in URL**. This is the link participants tap on
      their Android phone to install.
- [ ] Internal testing release → Roll out to Internal Testing.
      Approval is usually instant.
- [ ] Send the opt-in URL to participants via the channel agreed in
      the consent flow (e.g. study-coordinator email, not a public
      mailing list).

## 8. Post-release

- [ ] Tag the release in git: `git tag v3.7.28 -m "DopaX 3.7.28 (vc 114)"`
      and push the tag.
- [ ] Archive a copy of `app-release.aab` and `mapping.txt` outside
      the repo (e.g. encrypted shared drive). The mapping file is
      essential for de-obfuscating any crash report from a tester.
- [ ] Wait 24-48 h for Google's pre-launch report. Address any flags
      via the Console messages tab; you have 7 days for sensitive-API
      reviews before the app is auto-removed.
