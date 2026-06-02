# Google Play — Data Safety form answers

This is a paste-ready answer key for the Data Safety section of the Play
Console listing. Every claim here must match what the app actually does;
mismatches are a common cause of policy strikes.

Questions are taken from Play Console as of April 2026. Adjust if Google
re-orders them.

---

## 1. Does your app collect or share any of the required user data types?

**Yes.**

## 2. Is all user data collected by your app encrypted in transit?

**Yes.** All upload traffic uses HTTPS to a single Google Apps Script
endpoint. Cleartext HTTP is blocked by `network_security_config.xml`.

## 3. Do you provide a way for users to request that their data be deleted?

**Yes.** Settings → "Withdraw from study & delete my data" wipes all
on-device data immediately. Server-side data removal is handled by the
research team — contact email is in the in-app Privacy Policy.

---

## Data types collected

For each row, mark **Collected** = Yes, **Shared** = No (data goes only
to the study's research server), **Processing** = "Collected for
research", **Optional** = Yes (most are toggleable; users may withdraw
at any time).

| Category            | Type                          | Purpose              | Collected | Shared | Optional |
| ------------------- | ----------------------------- | -------------------- | --------- | ------ | -------- |
| Personal info       | Other info: age, gender       | App functionality, Analytics | Yes | No | Yes |
| Personal info       | Other info: pseudonymous user ID | App functionality | Yes | No | No (required to enroll) |
| Health and fitness  | Other health info: medications, dominant hand, PD-affected side | App functionality, Analytics | Yes | No | Yes |
| Health and fitness  | Other health info: motor-test results (spiral, hand turning, finger tapping, leg agility, TMT) | App functionality, Analytics | Yes | No | No (the test battery is the app) |
| Health and fitness  | Heart rate (if BLE/ANT+ HRM paired) | Analytics | Yes | No | Yes |
| App activity        | Other actions: keystroke timing & redacted category, NEVER literal characters | Analytics | Yes | No | Yes |
| App activity        | App interactions: foreground app package name during typing | Analytics | Yes | No | Yes |
| App activity        | Other user-generated content: questionnaire answers | Analytics | Yes | No | No (part of test battery) |
| Device or other IDs | Pseudonymous study ID generated on device | Analytics | Yes | No | No |
| Photos and videos   | (none)                        | —                    | No  | —  | —  |
| Audio files         | (none)                        | —                    | No  | —  | —  |
| Files and docs      | (none)                        | —                    | No  | —  | —  |
| Calendar            | (none)                        | —                    | No  | —  | —  |
| Contacts            | (none)                        | —                    | No  | —  | —  |
| Location            | (none)                        | —                    | No  | —  | —  |
| Web browsing        | (none)                        | —                    | No  | —  | —  |
| Financial info      | (none)                        | —                    | No  | —  | —  |
| Messages            | (none)                        | —                    | No  | —  | —  |

### Notes on tricky entries

**Photos / Videos = "No"** even though the camera permission is
requested. The face-distance feature processes camera frames on-device
via ML Kit and only the estimated cm value is saved — no frames are
stored or transmitted. Per Play Data Safety guidance, on-device-only
processing without storage or transmission does not count as collection.

**Audio = "No"** — DopaX never records audio. The app does *play* short
beeps via ToneGenerator during the leg-agility test; no audio capture.

**Location = "No"** — DopaX has no location permissions, never reads
GPS / Wi-Fi / cell ID, and never resolves IP to location.

**App activity / "Other actions"** is the Play Store's catch-all bucket.
Use this for the keystroke-timing stream — be explicit in the optional
"Description" field that the *literal characters typed are never
recorded*; only the category and millisecond timing are.

---

## Sensitive permissions disclosure (Play Console "Sensitive APIs" section)

For each permission, paste the matching justification text below into
the Console questionnaire.

### `BIND_ACCESSIBILITY_SERVICE`

This app uses an Accessibility Service to capture *redacted* keystroke
timing as a digital biomarker for Parkinson's disease. The service
records: (a) the wall-clock + monotonic timestamp of each keystroke,
(b) one of seven category labels (letter / digit / space / punctuation
/ backspace / enter / other), and (c) the package name of the app
being typed in. The service does NOT capture the literal characters
typed. Password fields are detected (`AccessibilityNodeInfo.isPassword`
+ InputType variant checks) and skipped entirely. A denylist of
sensitive packages (banking, password managers, secure messengers
that opt out) is also applied. The user grants this permission only
after reading a rationale dialog that states all of the above, and may
disable it from the Withdraw-From-Study button or system settings at
any time.

### `FOREGROUND_SERVICE_SPECIAL_USE`

DopaX runs three foreground services for ongoing physiological data
collection that must continue while the user's screen is off — sensor
collection (accelerometer / gyroscope / magnetometer at fastest rate),
optional ANT+ / BLE heart-rate monitor pairing, and optional
camera-based face-distance estimation. The visible notification states
which streams are active. Services stop immediately when the user
toggles them off in Settings, taps "Stop All Services", taps the
Withdraw button, or uninstalls the app.

### `POST_NOTIFICATIONS`

Used to post the daily test-battery prompts at the user-chosen times
and to display the foreground-service status notification.

### `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`

Used to fire the user's chosen daily test-prompt times precisely; the
test battery is most useful when run at consistent times of day, which
inexact alarms cannot guarantee under battery saver.

### `SYSTEM_ALERT_WINDOW`

Used to display a small recording-status indicator while the
(optional, currently disabled in this build) Visual Context feature is
active, so the user always knows when capture is on.

### `PACKAGE_USAGE_STATS`

Used to tag motor-test rows with the foreground app package name (e.g.
`com.whatsapp`), so analysts can correlate typing rhythm with the
context the user was typing in. Only the package name is read — never
the contents of those apps.

---

## Privacy Policy URL

Required field. Host the included `privacy_policy.html` on a stable
HTTPS URL controlled by your research group (e.g. a GitHub Pages site
or your university web host) and paste it here. A URL like
`https://parkinsons-research.example.org/dopax/privacy.html` is fine.

The Play Store strict requirement is that the URL is publicly
reachable, returns 200, and contains the privacy policy on its own
page (not behind a login or in the body of an unrelated page).
