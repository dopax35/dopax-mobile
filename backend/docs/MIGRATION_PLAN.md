# DopaX Backend Migration Plan

**Status:** Approved for Phase 0
**Branch:** `newArch`
**Author:** Management Agent → handoff to Backend Agent
**Target stack:** Node.js (TypeScript) + PostgreSQL + object storage
**Constraint:** 43 existing production users and all historical research data must be preserved.

---

## 0. Non-negotiable requirements

Every design choice below traces back to one of these four.

| # | Requirement | How it is satisfied | Verified in |
|---|---|---|---|
| **R1** | **Existing users keep logging in.** No password resets, no re-authentication, no account re-linking. | Firebase Auth remains the identity provider. The backend only *verifies* Firebase ID tokens. No credential is ever moved. | §4.1, Phase 1 |
| **R2** | **All existing data lands in PostgreSQL.** Auth accounts, Firestore profiles, and the full historical Google Drive corpus. | Idempotent, resumable importers plus a reconciliation report that must come back clean. | §8 Phase 2 |
| **R3** | **Both architectures run side by side**, controlled by `BOTH_ARCH`. Legacy Google Drive + Apps Script + CSV/Excel keeps working untouched while the new backend runs in parallel. Flip to backend-only once proven. | `BOTH_ARCH` master switch (§4.2) + research export job that keeps the CSV/Excel workflow intact (§4.3). | §4.2, Phase 3 |
| **R4** | **All development runs locally on the laptop.** Local PostgreSQL, local object storage, no cloud account required. | Docker Compose dev stack, `gdrive` storage passthrough so the corpus is never copied locally, documented device-to-laptop networking. | §5.3 |

**The governing principle for R3: the legacy path must never be made worse.** At no point does a
failure in the new backend cause a legacy upload to fail, retry, or be retained longer than it is
today. The new path is strictly additive until we flip.

---

## 1. Executive summary

DopaX/PDCollect has **no backend server today**. The two mobile clients write research data
to local CSV files, zip them per day, and push the ZIP through a hardcoded **Google Apps Script
web app** into a single **Google Drive folder**. Firebase is used only for authentication and a
small profile document.

This plan adds a Node.js API and a PostgreSQL system of record *alongside* that pipeline, proves
the two produce identical data, and only then retires the old path.

**Headline risks:** the entire research corpus lives in one un-inventoried Drive folder; participant
IDs exist in three incompatible formats with one known collision; and the Firebase password hash
parameters have not yet been exported.

---

## 2. Current state (as-is)

### 2.1 Components

| Component | Detail |
|---|---|
| Android client | `com.pdcollect.app`, Kotlin, v3.7.41 (versionCode 129) |
| iOS client | `com.oriw.pdcollect.ios1`, Swift, v3.7.40 (build 128) + keyboard extension |
| Firebase project | `dopa-x-app` (project number `225458522869`) |
| Server code | **None.** `backend/` is an empty directory skeleton (untracked, zero files) |

### 2.2 Data flow today

```
Device
  └─ CSV files in PDCollect/{participantId}/{yyyy-MM-dd}/
       └─ daily ZIP  PDData_{participantId}_{date}[_iOS].zip
            └─ POST  Google Apps Script  (action: getUploadUrl)
                 └─ PUT  resumable GCS URL
                      └─ Google Drive folder 1QLsYUTmXIha7rn7wNIJDXVTtrcWoXdly
                           └─ POST Apps Script (action: notify) → email
                                └─ researchers download ZIPs, analyse CSVs in Excel

Firebase Auth ──► Firestore users/{authUid}          (profile + dashboardMetrics)
              └─► Firestore user_mappings/{participantId}  (reverse index)
```

Firebase Storage is configured in both client config files but **is never used**.

### 2.3 What gets collected

Roughly 25–30 CSV schemas per participant-day, plus `.m4a` voice recordings inside the ZIP:

- **Active tests:** finger tapping, fingers test (camera), hand turning, leg agility, spiral
  tracing, trail-making (TMT), facial movement, voice test, voice sample
- **Passive streams:** IMU at 50 Hz (Android service) / 50–100 Hz (iOS device motion), touch
  events, app foreground/background events, screen state, keystroke rhythm (key *class* only,
  never characters), face distance, gaze, blink
- **Wearables/health:** BLE heart rate + RR, Beanie temperature and IMU, HealthKit gait /
  Health Connect, pedometer, motion activity, sleep, physical activity, medication log
- **iOS SensorKit** (research builds only): accelerometer, rotation rate, keyboard metrics,
  device usage
- **Self-report:** questionnaire, consent, profile snapshot

Volume: individual daily ZIPs can reach **1–2 GB**.

### 2.4 Known defects relevant to the migration

- Android Firestore sync **silently fails** once `dashboardMetrics` exceeds the Firestore 1 MiB
  document cap — long-running participants already lose cloud profile sync.
- iOS auto-upload defaulted to off until v3.7.13; some iOS participants have gaps.
- An Android `MainActivity.onResume()` crash loop caused partial CSV gaps from ~2026-07-03.
- Legacy iOS `key_events.csv` uses `letter`/`punctuation` where Android uses `char`/`punct`
  (non-retroactive schema change).
- Historical duplicate rows exist in `pedometer.csv` from a since-fixed backfill bug.
- "Reset & Withdraw" only clears the device; uploaded Drive data is never deleted. This is a
  compliance gap the new backend must close.

---

## 3. Existing users — migration inventory

Source: `users.json` (Firebase Auth export) and `correlated_users_files.csv`.

| Metric | Value |
|---|---|
| Firebase Auth accounts | **43** |
| Likely real participants | ~24 (remainder are `Test User` / `explore_*` / `*@example.com`) |
| Email + password | 22 (scrypt hashes present) |
| Google sign-in | 18 |
| Apple sign-in | 3 |
| Account creation range | 2026-05-26 → 2026-07-30 |
| Participant ID ≠ Auth UID | **15 of 43** |

### 3.1 Three participant ID formats in production

| Format | Count | Example | Origin |
|---|---|---|---|
| Firebase Auth UID (28 chars) | 28 | `DmZLr8ymaffMcamu5AuDrB1DzB82` | Early builds |
| 6-char uppercase hex | 12 | `9EEBCD`, `42976F` | Android `UUID.randomUUID().substring(0,6)` |
| `pd_` + 8 lowercase hex | 3 | `pd_53a21c75` | iOS `"pd_" + UUID().prefix(8)` |

### 3.2 Blocking data issue: ID collision

`pd_53a21c75` maps to **two distinct auth accounts**:

- `KN3JT0d9PIX4ZtjKvbllQlpc3f53` — `hagaishtinberg@gmail.com`
- `OA5r4jqkUNa38HoFHlLhiIJfP4b2` — `npj9hshw7f@privaterelay.appleid.com`

Both match upload pattern `PDData_pd_53a21c75_*.zip`. **Must be disambiguated manually in
Phase 0** (probably by upload date ranges and device platform) or their research data will be
merged into one participant.

### 3.3 Migration principle for IDs

Do **not** renumber. Existing `participant_code` values are preserved verbatim so that historical
Drive filenames still correlate. All three legacy formats are additionally recorded in a
`legacy_file_user_ids[]` array so any old filename resolves to exactly one participant. Only
*new* participants get the uniform new format.

---

## 4. Locked decisions

| Decision | Choice |
|---|---|
| Authentication | **Keep Firebase Auth as identity provider** (R1). Backend verifies Firebase ID tokens; no password re-import in this project. Self-hosted auth deferred indefinitely. |
| Raw data storage | **Two-tier.** Raw ZIPs and extracted CSVs in object storage; PostgreSQL holds identities, sessions, events, and derived metrics. |
| Legacy coexistence | **`BOTH_ARCH` master switch** (R3). Dual-run with nightly reconciliation, flip to backend-only only after 14 consecutive clean days. |
| Development environment | **Local-first** (R4). Docker Compose on the laptop. No cloud account needed through Phase 5. |
| Hosting | **Deferred to Phase 6.** Candidates: Azure, AWS, Railway. Everything is built cloud-agnostic. |

### 4.1 R1 — Login continuity guarantee

Nothing about authentication changes for existing users. Firebase Auth stays exactly as it is; the
backend adds a verification step and nothing else:

```
Client → Firebase SDK (unchanged) → Firebase ID token
       → POST /v1/auth/session  { idToken }
       → backend verifies via firebase-admin, resolves participant, issues its own short-lived JWT
```

Resolution order when a token arrives: `auth_identities.firebase_uid` → `participants` via
`legacy_file_user_ids` → create new participant. A user whose participant ID differs from their
auth UID (15 of 43) resolves correctly through the second path.

**Acceptance tests, all of which must pass before Phase 3:**

- All 22 email/password users sign in with their existing password, unchanged.
- All 18 Google and 3 Apple users sign in through their existing provider.
- An existing signed-in session on a device that updates to the new build is **not** invalidated.
- A user whose `participant_code` ≠ Firebase UID resolves to their existing historical data.
- `KN3JT0d9PIX4ZtjKvbllQlpc3f53` and `OA5r4jqkUNa38HoFHlLhiIJfP4b2` resolve to two *different*
  participants despite sharing `pd_53a21c75`.

No credential, password hash, or OAuth linkage is written or migrated at any point.

### 4.2 R3 — The `BOTH_ARCH` switch

One master switch governs whether the legacy architecture runs alongside the new one.

```
BOTH_ARCH=true   →  legacy Drive/Apps Script/Excel pipeline is authoritative,
                    new backend runs in parallel and is continuously reconciled
BOTH_ARCH=false  →  new backend is authoritative, client dual-write stops
```

**Backend behaviour** (`BOTH_ARCH` read from the environment at boot, surfaced on `/v1/config`):

| Behaviour | `true` | `false` |
|---|---|---|
| Accept uploads on `/v1/uploads` | yes | yes |
| Drive drain worker ingests legacy uploads | yes, continuous | only while `LEGACY_DRIVE_DRAIN=true` (Phase 5 tail) |
| Nightly reconciliation job | yes | no |
| Research CSV/Excel export job (§4.3) | yes | yes |
| Write anything back to Drive | export artifacts only, never deletes | no |
| Source of truth on conflict | **legacy Drive** | **PostgreSQL** |
| `/v1/config` tells clients to dual-write | `true` | `false` |

**Mobile clients.** Mobile apps have no environment variables, so `BOTH_ARCH` maps to a build-time
flag with a server-side override, letting us flip without shipping a release:

- Android: `buildConfigField("boolean", "BOTH_ARCH", ...)` from a Gradle property → `BuildConfig.BOTH_ARCH`
- iOS: a build setting surfaced through `Info.plist`, read at launch
- Both: overridden at runtime by `bothArch` in the `GET /v1/config` response, cached locally so
  the app behaves correctly offline

When dual-write is on, the client zips the day exactly as it does now and uploads it to **both**
destinations, with **independent success markers**:

```
.uploaded      ← written on legacy Apps Script success   (existing behaviour, UNCHANGED)
.uploaded_v2   ← written on new backend success          (new, independent retry schedule)
```

This is the critical safety property. A backend outage produces a missing `.uploaded_v2` and a
retry; it can never block the legacy upload, delay the existing retention cleanup, or cause data
loss. Retention deletion continues to key off `.uploaded` alone until `BOTH_ARCH=false`.

**Reconciliation.** A nightly job compares the Drive inventory against PostgreSQL per participant
per day and records the result in `reconciliation_runs`. The report covers: objects present on
Drive but missing in the DB, uploads present in the DB but absent from Drive, byte-count and
row-count mismatches, and parse failures.

**Exit condition for flipping to `false`:** 14 consecutive nightly reconciliation runs with zero
discrepancies across all active participants, plus a signed-off spot check where a researcher
reproduces a real analysis from the new backend's export and gets identical numbers.

The flip is reversible: setting `BOTH_ARCH=true` again restores dual-run, and the Drive folder is
never mutated or deleted during any of this.

### 4.3 R3 — Keeping the CSV/Excel research workflow intact

Researchers today download ZIPs from Drive and work on the CSVs in Excel. That workflow must
survive the migration, so the backend ships a **research export** component from Phase 2 onward,
not as an afterthought:

- **Raw-fidelity export** — regenerates per-participant, per-day CSVs with the legacy column order
  and headers preserved byte-for-byte, including the historical iOS `letter`/`punctuation` vs.
  Android `char`/`punct` discrepancy. Anything already written stays reproducible.
- **Normalised export** — the same data with cross-platform inconsistencies resolved, for new
  analysis.
- **Excel workbooks** — one `.xlsx` per participant with a sheet per data type, generated via
  `exceljs`, so the team can open a participant's whole history in one file instead of unzipping
  dozens of folders.
- **Delivery** — `GET /v1/admin/exports/...` for on-demand download, plus a scheduled job that,
  while `BOTH_ARCH=true`, writes the exports back into the same Drive folder structure so existing
  links and spreadsheets keep resolving.

Acceptance: for any given participant-day, the export produced from PostgreSQL is byte-identical
to the CSVs inside the original Drive ZIP. This doubles as the strongest possible proof that
R2 succeeded.

---

## 5. Target architecture

```
Mobile clients (Android / iOS)
   │
   ├─ GET  /v1/config                 bothArch flag, API base, kill switch
   ├─ POST /v1/auth/session           Firebase ID token → backend JWT   (R1)
   ├─ PUT  /v1/participants/me/profile
   ├─ POST /v1/events                 batched user-action telemetry
   │
   ├─ Legacy path (while BOTH_ARCH=true, unchanged)
   │     Apps Script → Google Drive → .uploaded
   │
   └─ New path (additive)
         POST /v1/uploads             → { uploadId, parts[] }
         PUT  <presigned part URLs>   → object storage, directly, resumable
         POST /v1/uploads/{id}/complete → .uploaded_v2

Fastify API (Node 22 LTS, TypeScript, container)
   ├─ PostgreSQL 16   system of record
   ├─ pg-boss         job queue (lives in Postgres, no extra infra)
   └─ StorageAdapter  gdrive | minio | s3 | azure

Workers (same image, different entrypoint)
   ├─ Ingestion    ZIP → checksum → extract → parse ~30 CSV schemas
   │                   → COPY into Postgres → archive extracted CSVs
   ├─ Drive drain  polls the legacy folder, ingests via the same pipeline
   ├─ Reconciler   nightly Drive-vs-Postgres diff → reconciliation_runs
   └─ Exporter     regenerates legacy-format CSVs and .xlsx workbooks
```

### 5.1 Technology choices and rationale

| Concern | Choice | Why |
|---|---|---|
| HTTP framework | Fastify | Best-in-class streaming and schema validation; matches the dependencies of the abandoned scaffold |
| Language | TypeScript, Node 22 LTS | |
| DB access / migrations | Drizzle ORM + drizzle-kit | SQL-first; ORMs handle bulk `COPY` ingestion badly |
| Job queue | pg-boss | No Redis; runs inside Postgres, so the laptop dev stack stays to two containers |
| Validation | Zod, shared with route schemas | One source of truth for the API contract |
| Auth | `firebase-admin` token verification → short-lived backend JWT | R1; zero risk to existing logins |
| Excel generation | exceljs | R3 research workflow continuity |
| Logging | pino + OpenTelemetry | |
| Testing | Vitest + Testcontainers (real Postgres) | |

### 5.2 Cloud-agnostic by construction

Two choices make the deferred hosting decision essentially free:

- **pg-boss** puts the job queue inside PostgreSQL, so there is no SQS / Service Bus / Redis
  dependency to port.
- **Two-tier storage** means no TimescaleDB, so plain managed PostgreSQL 16 works everywhere
  (AWS RDS does not support the Timescale extension; this would otherwise have forced the
  decision early).

The only cloud-specific surface is object storage, isolated behind one `StorageAdapter` interface:

| Backend | Used for |
|---|---|
| `minio` | Local development (S3 API on the laptop) |
| `gdrive` | Passthrough — raw ZIP stays on Drive, only parsed rows land in Postgres (see §5.3) |
| `s3` | AWS S3, Cloudflare R2, or any S3-compatible production target |
| `azure` | Azure Blob Storage |

### 5.3 R4 — Local development environment

Everything runs on the laptop. No cloud account is needed through Phase 5.

**Dev stack** — `backend/docker-compose.yml`:

| Service | Image | Purpose |
|---|---|---|
| `postgres` | `postgres:16` | System of record, volume-mounted to `backend/.tmp/pgdata` |
| `minio` | `minio/minio` | S3-compatible object storage on `localhost:9000` |
| `adminer` | `adminer` | Optional SQL browser |

Native Homebrew `postgresql@16` is a supported fallback; the `backend/.tmp/pgdata` path already
exists in the working tree from an earlier attempt and is reused as the Docker volume mount.

**The disk problem, and how we avoid it.** The Drive corpus is un-inventoried and daily ZIPs run
1–2 GB, so it very likely does not fit on a laptop. We therefore do **not** mirror it locally.
With `STORAGE_BACKEND=gdrive`, the ingestion worker streams each ZIP from Drive, parses it in
memory (bounded, one CSV at a time), writes the parsed rows to Postgres, and discards the bytes.
`uploads.object_key` stores the Drive file id and `uploads.storage_backend` records `gdrive`.
The parsed relational data is small — comfortably laptop-sized — while the raw bytes stay where
they already are. Switching to `s3` or `azure` later is a config change plus a one-time copy job.

**Getting a phone to talk to the laptop.** `localhost` is not reachable from a physical device, so
Phase 3 needs this set up in advance rather than discovered late:

- Find the LAN IP with `ipconfig getifaddr en0`; the API base becomes `http://<lan-ip>:8080`.
- Android emulator reaches the host at `10.0.2.2`. Physical Android devices on the same Wi-Fi need
  a **debug-only** `network_security_config.xml` permitting cleartext to that IP. The release
  config stays HTTPS-only.
- iOS Simulator reaches `localhost` directly. A physical iPhone needs `NSAllowsLocalNetworking`
  in a **debug-only** ATS exception, plus the local-network permission prompt on iOS 14+.
- Alternatively `cloudflared tunnel` or `ngrok` gives a real HTTPS URL and sidesteps both ATS and
  cleartext configuration. Recommended when testing on a device that is not on the same Wi-Fi.

**Internet is still required for two things** even in local mode: `firebase-admin` fetches Google's
public signing certificates to verify ID tokens (cached, but the first call needs network), and the
Drive API for ingestion. A documented `AUTH_DEV_BYPASS` mode exists for fully-offline work and is
hard-disabled unless `NODE_ENV=development`.

**Local backups matter here.** While development is laptop-only, that Postgres instance holds the
migrated corpus. A `pg_dump` script runs on a schedule into a local directory, and the dump path
is excluded from git.

**Environment variables** (`backend/.env.example`):

```bash
NODE_ENV=development
PORT=8080

BOTH_ARCH=true                      # R3 master switch
LEGACY_DRIVE_DRAIN=true             # Phase 5 tail; keep on until old builds die out

DATABASE_URL=postgres://dopax:dopax@localhost:5432/dopax

STORAGE_BACKEND=gdrive              # gdrive | minio | s3 | azure
MINIO_ENDPOINT=http://localhost:9000
MINIO_ACCESS_KEY=
MINIO_SECRET_KEY=

FIREBASE_PROJECT_ID=dopa-x-app
GOOGLE_APPLICATION_CREDENTIALS=./secrets/serviceAccountKey.json

LEGACY_DRIVE_FOLDER_ID=1QLsYUTmXIha7rn7wNIJDXVTtrcWoXdly
LEGACY_APPS_SCRIPT_URL=

JWT_SECRET=
AUTH_DEV_BYPASS=false
```

`backend/secrets/` and `backend/.env` are git-ignored. No credential is ever committed.

---

## 6. Data model (schema v1)

Two tiers. PostgreSQL is the **queryable** record; object storage (or Drive, in passthrough mode)
is the **immutable** record.

### 6.1 Identity and profile

```sql
create table participants (
  id                    uuid primary key default gen_random_uuid(),
  participant_code      text not null unique,          -- preserved verbatim from production
  legacy_file_user_ids  text[] not null default '{}',  -- all historical ID forms
  cohort                text,
  status                text not null default 'active', -- active | withdrawn | archived
  is_test_account       boolean not null default false,
  enrolled_at           timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index participants_legacy_ids_idx on participants using gin (legacy_file_user_ids);

create table auth_identities (
  id              uuid primary key default gen_random_uuid(),
  participant_id  uuid not null references participants(id) on delete cascade,
  provider        text not null,        -- password | google.com | apple.com
  provider_uid    text,
  firebase_uid    text unique,
  email           text,
  email_verified  boolean not null default false,
  display_name    text,
  password_hash   text,                 -- captured for safekeeping only; never used (R1)
  password_salt   text,
  hash_config     jsonb,                -- project scrypt params, captured in Phase 0
  created_at      timestamptz,
  last_sign_in_at timestamptz,
  unique (provider, provider_uid)
);
```

`age` is an integer on Android and a string on iOS. It normalises to `smallint`; the original
value is retained in `settings` so nothing is lost.

```sql
create table participant_profiles (
  participant_id  uuid primary key references participants(id) on delete cascade,
  revision        integer not null default 1,   -- powers local-wins merge, see §7.2
  age             smallint,
  gender          text,
  dominant_hand   text,
  affected_side   text,
  medications     jsonb not null default '[]',
  signature_name  text,
  settings        jsonb not null default '{}',  -- test times, toggles, BLE pairings, raw values
  updated_at      timestamptz not null default now(),
  updated_by_device uuid
);
create table participant_profile_history (like participant_profiles including all);
```

Consent is an **append-only audit trail**, not a boolean. This is a medical study; we must be able
to prove what was consented to and when.

```sql
create table consents (
  id               uuid primary key default gen_random_uuid(),
  participant_id   uuid not null references participants(id),
  document_version text not null,
  document_hash    text not null,
  signature_name   text not null,
  granted_at       timestamptz not null,
  revoked_at       timestamptz,
  platform         text,
  app_version      text
);
```

### 6.2 Devices and uploads

```sql
create table devices (
  id                 uuid primary key default gen_random_uuid(),
  participant_id     uuid not null references participants(id) on delete cascade,
  device_install_id  text not null,
  platform           text not null,       -- android | ios
  model              text,
  os_version         text,
  app_version        text,
  first_seen_at      timestamptz not null default now(),
  last_seen_at       timestamptz not null default now(),
  unique (participant_id, device_install_id)
);

create table uploads (
  id                    uuid primary key default gen_random_uuid(),
  participant_id        uuid not null references participants(id),
  device_id             uuid references devices(id),
  platform              text not null,
  collection_date       date not null,
  filename              text not null,
  storage_backend       text not null default 'gdrive',  -- gdrive | minio | s3 | azure
  object_key            text,                            -- Drive file id, or bucket key
  legacy_drive_file_id  text,                            -- retained even after copy to blob
  bytes                 bigint,
  sha256                text,
  upload_session_id     text,
  source                text not null default 'api',     -- api | drive_backfill | drive_drain
  status                text not null default 'pending',
                        -- pending | uploading | stored | parsing | parsed | failed
  received_at           timestamptz,
  parsed_at             timestamptz,
  error                 text,
  unique (participant_id, collection_date, platform)     -- idempotency key
);

create table upload_files (
  id          uuid primary key default gen_random_uuid(),
  upload_id   uuid not null references uploads(id) on delete cascade,
  path_in_zip text not null,
  kind        text not null,     -- csv schema name | voice_audio | json | crash_log
  row_count   integer,
  bytes       bigint
);
```

The `unique (participant_id, collection_date, platform)` constraint is what makes the whole
pipeline safely retryable, and it is what prevents dual-write from double-counting: the same
participant-day arriving via both the client API and the Drive drain worker collapses to one row.

### 6.3 Reconciliation (R3)

```sql
create table reconciliation_runs (
  id                uuid primary key default gen_random_uuid(),
  run_at            timestamptz not null default now(),
  mode              text not null,          -- both_arch | backend_only
  drive_objects     integer not null,
  drive_bytes       bigint not null,
  db_uploads        integer not null,
  db_parsed         integer not null,
  missing_in_db     jsonb not null default '[]',
  missing_in_drive  jsonb not null default '[]',
  mismatched        jsonb not null default '[]',
  status            text not null           -- clean | discrepancies | failed
);
```

Fourteen consecutive `clean` runs is the gate for `BOTH_ARCH=false`.

### 6.4 User-action monitoring

This is the table that delivers "save and monitor all the users actions". It is partitioned
monthly and carries a client-supplied `dedupe_key` so retries and dual-write never double-count.

```sql
create table events (
  id              bigserial,
  participant_id  uuid not null references participants(id),
  device_id       uuid references devices(id),
  occurred_at     timestamptz not null,   -- client clock
  received_at     timestamptz not null default now(),
  event_type      text not null,
  session_id      uuid,
  app_version     text,
  payload         jsonb not null default '{}',
  dedupe_key      text not null,
  primary key (id, occurred_at)
) partition by range (occurred_at);

create unique index events_dedupe_idx on events (dedupe_key, occurred_at);
create index events_participant_time_idx on events (participant_id, occurred_at desc);
create index events_type_time_idx on events (event_type, occurred_at desc);
create index events_payload_idx on events using gin (payload);
```

**Event taxonomy (v1):**

| Group | Event types |
|---|---|
| Lifecycle | `app_opened`, `app_backgrounded`, `session_started`, `session_ended` |
| Onboarding | `consent_viewed`, `consent_granted`, `profile_completed`, `walkthrough_completed` |
| Auth | `sign_in_succeeded`, `sign_in_failed`, `sign_in_skipped`, `sign_out` |
| Tests | `test_started`, `test_completed`, `test_abandoned`, `test_failed` |
| Self-report | `questionnaire_submitted`, `medication_logged`, `activity_logged` |
| Collection | `collection_started`, `collection_stopped`, `permission_granted`, `permission_denied` |
| Devices | `ble_device_paired`, `ble_device_disconnected` |
| Sync | `upload_started`, `upload_succeeded`, `upload_failed`, `profile_synced` |
| Health | `crash_reported`, `background_task_ran` |

Events are emitted in near real time (batched, offline-queued on device), which is what finally
makes remote monitoring of participant adherence possible — today there is no way to know a
participant stopped using the app until their ZIPs stop arriving.

### 6.5 Research results

```sql
create table test_sessions (
  id              uuid primary key default gen_random_uuid(),
  participant_id  uuid not null references participants(id),
  device_id       uuid references devices(id),
  upload_id       uuid references uploads(id),
  test_type       text not null,   -- finger_tapping | hand_turning | spiral_tracing |
                                   -- leg_agility | fingers_test | tmt | voice | facial_movement
  started_at      timestamptz not null,
  ended_at        timestamptz,
  duration_ms     integer,
  side            text,
  dominant_hand   text,
  affected_side   text,
  completed       boolean not null default false,
  metrics         jsonb not null default '{}',
  raw_object_key  text,
  unique (participant_id, test_type, started_at)
);

create table test_metrics (
  session_id   uuid not null references test_sessions(id) on delete cascade,
  metric_key   text not null,
  metric_value double precision,
  primary key (session_id, metric_key)
);
```

Low-volume self-report data is fully normalised: `questionnaire_responses`, `medication_logs`,
`physical_activity_logs`, `sleep_logs`, `heart_rate_summaries`.

`daily_summaries` replaces the Firestore `dashboardMetrics` map and removes the 1 MiB cap that is
already breaking sync for long-running participants:

```sql
create table daily_summaries (
  participant_id uuid not null references participants(id),
  day            date not null,
  metrics        jsonb not null default '{}',
  computed_at    timestamptz not null default now(),
  primary key (participant_id, day)
);
```

High-rate streams (IMU, gaze, touch, keystroke) are **not** loaded into Postgres in v1. They stay
as CSVs inside the archived ZIP, addressable via `upload_files`. If a specific stream later needs
SQL access, we add a monthly-partitioned table for that stream only and backfill it with `COPY`.

### 6.6 Compliance

```sql
create table staff_users (...);   -- dashboard access
create table audit_log (
  id          bigserial primary key,
  actor_type  text not null,      -- staff | participant | system
  actor_id    text,
  action      text not null,
  subject     text,
  occurred_at timestamptz not null default now(),
  metadata    jsonb
);
```

Every staff read of participant data is audited.

---

## 7. API contract (v1)

Deliberately shaped to mirror the existing Apps Script protocol so that the client diff in Phase 3
stays small.

### 7.1 Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/v1/config` | `bothArch`, API base, minimum supported app version, kill switch |
| `POST` | `/v1/auth/session` | Firebase ID token → backend access + refresh JWT (R1) |
| `POST` | `/v1/auth/refresh` | Rotate access token |
| `GET` | `/v1/participants/me` | Participant + profile |
| `PUT` | `/v1/participants/me/profile` | Revision-checked profile write |
| `POST` | `/v1/participants/me/consent` | Append consent record |
| `POST` | `/v1/devices` | Register / heartbeat device |
| `POST` | `/v1/events` | Batched action telemetry (up to 500 per request) |
| `POST` | `/v1/uploads` | Begin upload → `{ uploadId, parts[] }` (replaces `getUploadUrl`) |
| `POST` | `/v1/uploads/{id}/complete` | Finalise + enqueue parse (replaces `notify`) |
| `GET` | `/v1/uploads?since=` | Which dates the server already has (drives `.uploaded_v2`) |
| `GET` | `/v1/participants/me/summaries` | Dashboard trend series |
| `DELETE` | `/v1/participants/me` | Withdraw — closes the current compliance gap |
| `GET` | `/v1/admin/exports/...` | CSV / `.xlsx` research exports (§4.3) |
| `GET` | `/v1/admin/reconciliation` | Latest reconciliation runs (§4.2) |
| `GET` | `/v1/admin/*` | Monitoring dashboard (staff auth + audit) |

### 7.2 Profile merge semantics

The iOS client already uses local-wins merge on sign-in to avoid the v3.7.29 regression that
blanked profiles. We preserve that behaviour: `PUT /v1/participants/me/profile` requires the
client's last-known `revision`. A mismatch returns `409` with the server document, and the client
merges locally and retries. No silent overwrites in either direction.

### 7.3 Upload transport

Current production uses a single resumable `PUT` to a GCS URL handed out by Apps Script. Neither
S3 nor Azure Blob offers that exact shape, so v1 uses **multipart upload with presigned part URLs**
(S3 `UploadPart` / Azure `Put Block` + `Put Block List`). This is strictly better for 1–2 GB files
on mobile networks because a failed part retries alone instead of restarting the whole transfer.

This is the single largest client-side change in Phase 3 and should be estimated accordingly.

---

## 8. Phased execution

### Phase 0 — Inventory and freeze (3–5 days, blocking)

No code. Pure read-only investigation, and everything downstream depends on it.

1. **Export Firebase Auth with hash parameters.** Run `firebase auth:export users_full.json
   --format=json --project dopa-x-app`. The existing `users.json` in the repo **does not contain
   `hash_config`**. Even though R1 means we never migrate credentials, capture these now: if the
   Firebase project is ever lost, the 22 password accounts become unrecoverable.
2. **Paginated Firestore export** of `users` and `user_mappings`. The existing scripts request
   `pageSize=500` with no pagination loop; fine at 43 users, silently lossy above 500.
3. **Full Google Drive inventory** of folder `1QLsYUTmXIha7rn7wNIJDXVTtrcWoXdly` via the Drive
   API: file id, name, size, md5, created time. This is the actual research corpus and we
   currently have **no idea how large it is** — the number determines whether §5.3's `gdrive`
   passthrough is a convenience or a hard necessity.
4. **Resolve the `pd_53a21c75` collision** (see §3.2) and produce a documented mapping.
5. **Classify test vs. real accounts** and record the decision in a reviewable CSV.
6. **Capture the legacy CSV schemas** exactly as they appear in real ZIPs — this is the reference
   the §4.3 raw-fidelity export is diffed against.
7. Update `AGENTS.md`, which currently instructs the DevOps agent to deploy the backend to
   Firebase — no longer correct.

**Exit criteria:** Drive manifest exists with total object count and byte volume; auth export with
`hash_config` is stored securely; the ID collision has a documented resolution.

### Phase 1 — Backend foundation, local (2 weeks)

Backend Agent. Nothing user-visible; runs entirely on the laptop (R4).

- Fastify + TypeScript scaffold in `backend/` (the existing empty skeleton is discarded and
  rebuilt), Drizzle migrations for schema v1, pg-boss wiring.
- Docker Compose dev stack: Postgres 16 + MinIO, `.env.example`, one-command bootstrap.
- `StorageAdapter` with `gdrive`, `minio`, `s3`, and `azure` implementations.
- Firebase ID token verification and participant resolution, including the `legacy_file_user_ids`
  fallback path.
- `BOTH_ARCH` plumbing and `GET /v1/config`.
- Health probes, structured logging, error tracking.
- Vitest + Testcontainers integration suite against real PostgreSQL.
- CI: lint, typecheck, test, build container image.

**Exit criteria:** on `localhost`, a real device can sign in with an **existing production account**,
register, write a profile, post events, and complete a multipart upload end to end. All five R1
acceptance tests in §4.1 pass. Code Reviewer sign-off.

### Phase 2 — Backfill all existing data (2 weeks) — R2

Every importer is idempotent and resumable; all of them can be re-run safely.

- Auth export → `participants` + `auth_identities`, preserving `participant_code` and populating
  `legacy_file_user_ids`.
- Firestore export → `participant_profiles` + `consents`.
- Drive manifest → `uploads` rows with `storage_backend='gdrive'`, then stream each ZIP from Drive
  through the parse pipeline into sessions, events, and summaries — **without persisting the raw
  bytes locally** (§5.3).
- Build the §4.3 exporter and prove round-trip fidelity.

**Exit criteria:** 100% of Drive objects accounted for in `reconciliation_runs`; for a sample of
participant-days spanning both platforms and the full date range, the regenerated CSV export is
byte-identical to the CSVs inside the original ZIP.

### Phase 3 — Client dual-write with `BOTH_ARCH=true` (2 weeks build + 2–3 weeks soak) — R3

iOS Agent and Android Agent, in parallel.

- `BOTH_ARCH` build flag on both platforms, with the `/v1/config` runtime override.
- Add the new upload path (multipart presigned) **alongside** the untouched Apps Script path, with
  the independent `.uploaded` / `.uploaded_v2` markers described in §4.2.
- Add `PUT /v1/participants/me/profile` alongside the existing Firestore write.
- Add the offline-queued, batched `EventLogger` emitting the §6.4 taxonomy.
- Local-network setup for physical devices per §5.3.
- Nightly reconciliation reviewed every morning.

**Exit criteria:** 14 consecutive clean reconciliation runs across all active participants, and a
researcher reproduces a real analysis from the new export with identical numbers.

### Phase 4 — Flip to `BOTH_ARCH=false` (1 week)

- Set `BOTH_ARCH=false`. Client dual-write stops; PostgreSQL becomes the source of truth.
- Stop Firestore writes; Firestore becomes a read-only historical backup.
- Apps Script and the Drive folder remain live and untouched — **nothing is deleted**.
- The flip is reversible for the entire phase; if anything looks wrong, set it back to `true`.

### Phase 5 — Drain and decommission (ongoing, ~6–8 weeks)

Participants on old builds keep uploading to Apps Script indefinitely — this is the step that is
usually forgotten and it is why nothing is deleted early.

- `LEGACY_DRIVE_DRAIN=true` keeps the drain worker polling the legacy folder and ingesting late
  arrivals through the same pipeline (`source = 'drive_drain'`).
- Track adoption by app version. Once the drain worker has seen nothing new for 30 days, retire
  the Apps Script deployment and archive the Drive folder to cold storage.

### Phase 6 — Production hosting and monitoring dashboard

- Hosting decision (Azure / AWS / Railway), driven mainly by whether the study needs a HIPAA BAA
  or has a data-residency requirement.
- One-time copy job moving raw objects from `gdrive` passthrough into the chosen blob store.
- Staff web dashboard: enrolment and adherence, per-participant timelines from `events`, upload
  health and gap detection, data-quality flags, consent and withdrawal management, audit trail.

### Phase 7 — Deferred

Self-hosted authentication (R1 means this is explicitly *not* in scope now), and raw sensor stream
loading into partitioned tables if research demand justifies it.

---

## 9. Timeline

```
Week  1   2   3   4   5   6   7   8   9  10  11  12
P0   ██
P1       ████████
P2               ████████
P3                       ████████░░░░░░░░           (build ████ / soak ░░░░)
P4                                       ██          BOTH_ARCH=false
P5                                         ████████████►
P6                                         ────────────►
```

**~9–10 weeks to the `BOTH_ARCH=false` flip**, all of it on the laptop. Phase 0 starts immediately;
it needs no hosting decision and no code.

---

## 10. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Drive corpus size is unknown | Could invalidate the Phase 2 estimate and exceed laptop disk | Phase 0 inventory gates everything; `gdrive` passthrough means we never copy it locally (§5.3) |
| `hash_config` never exported and the Firebase project is later lost | 22 password users permanently unrecoverable | Export in Phase 0 even though R1 means we never use it |
| `pd_53a21c75` collision | Two participants' research data merged | Manual resolution in Phase 0; explicit R1 acceptance test |
| New backend failure blocks the legacy upload | Data loss during dual-run — the worst outcome | Independent `.uploaded` / `.uploaded_v2` markers; retention keys off `.uploaded` only until the flip |
| Dual-write double-counting | Corrupted analysis | `dedupe_key` on events; `(participant_id, collection_date, platform)` unique on uploads |
| 1–2 GB uploads through the API server | Timeouts, memory exhaustion | Presigned multipart direct to storage; bytes never traverse the API |
| Old app builds keep using Apps Script | Silent data loss after decommission | Drive drain worker + 30-day no-new-files rule before retirement |
| Laptop-only Postgres holds the migrated corpus | Total loss on disk failure | Scheduled local `pg_dump`; Drive remains the untouched source of truth until Phase 5 |
| Researchers' Excel workflow breaks | Study disruption, loss of trust | §4.3 export component built in Phase 2, not after; byte-identical fidelity is an exit criterion |
| Health data compliance (IRB, encryption, residency) | Study jeopardy | Encryption at rest and in transit, append-only consent, audit log, working withdrawal endpoint; confirm residency before the Phase 6 hosting decision |
| Clock skew on client timestamps | Misordered event timelines | Store both `occurred_at` and `received_at`; flag implausible skew during ingest |

---

## 11. Open items

1. **Drive API access** — a service account with read access to the folder, needed for Phase 0.
   `export_users_csv.py` references a `serviceAccountKey.json` that is not in the repo.
2. **Firebase CLI access** for the auth and Firestore exports.
3. **Data retention policy** — how long raw ZIPs are kept, and what withdrawal must actually delete.
4. **Test account disposition** — delete, or retain flagged as `is_test_account`?
5. **Hosting** — deferred to Phase 6, but the HIPAA BAA and data-residency questions should be
   answered before then (several participants appear to be in Israel).
6. **Figma** for the UI/UX refactor. The dashboard endpoints in §7.1 should be validated against
   the new designs before the schema is frozen, so the refactor needs no backend changes.

---

## 12. Agent handoffs

| Phase | Owner |
|---|---|
| 0 | Management Agent (inventory, decisions) |
| 1–2 | Backend Agent → Code Reviewer |
| 3 | iOS Agent + Android Agent → Code Reviewer |
| 4–5 | DevOps Agent (flag flip, drain, decommission) |
| 6 | DevOps Agent (hosting) + Backend Agent + UX/UI Designer |

Per `AGENTS.md`, every phase exits through the Code Reviewer before reaching the DevOps Agent.
`AGENTS.md` itself must be updated in Phase 0: it currently names Firebase as the backend
deployment target, which this plan supersedes.
