# Amos's Architecture — What We Have and What Is Missing

Reviewed 17 Aug 2026 · **30 requirements from his email: 14 done, 5 partly, 10 not built, 1 done
differently** · plus 3 open questions (2 his, 1 for the ethics board).

---

## 1. What we have

One PostgreSQL 16 database. 24 tables, 25 links between them, two schemas.

`participants.participant_code` is the patient's fake ID. Every table that holds patient data points
at it. No patient's real name, email or phone number can be read from the research side.

| Group | Tables | What it is for |
|---|---|---|
| `identity` schema | 3 | The locked half: who the patient really is, and their signed consents |
| Participants | 4 | The fake ID, plus age, gender, affected side, medications |
| Asset catalog | 5 | One row per uploaded ZIP, one row per file inside it |
| Research data | 9 | Medication doses, test scores, questionnaires, sleep, activity, heart rate, events |
| Operations | 3 | Staff accounts, audit log, import bookkeeping |

**Three things worth knowing:**

1. **Identity is in its own schema.** `auth_identities`, `consents` and `email_otp_codes` were moved
   out of the research schema. A researcher account cannot read them at all — PostgreSQL blocks it,
   not our code. A few identifying columns had to stay on the research side, and those are blocked
   one by one: `signature_name` and `settings` on profiles, the whole of `staff_users`, `audit_log`,
   `participant_profile_history` and `participant_id_conflicts`.
2. **Deleting a patient is refused, on purpose.** Study data is never auto-deleted with the patient.
   That is why erasing someone needs a proper routine, not a `DELETE`. Only their login row, profile,
   profile history and device records follow them out.
3. **Production still uploads to Google Drive, not to us.** Our backend reads and catalogs that data.
   It does not receive uploads yet. This is the reason most of the missing items below are missing.

---

## 2. Amos's requirements, one by one

**Status words:** *Done* · *Partly* (what is missing is named) · *Not built* · *Different* (we chose
another way).

### The two halves he said matter most

| He asked for | Us | What we have |
|---|---|---|
| One catalog row per file | Partly | Right shape, and 6 of his 8 columns. Missing: device (only the app can tell us) and real storage path (still a Drive file ID) |
| Files only ever use the fake ID | **Done** | `uploads` and `upload_files` hold the fake ID and nothing else |
| Real identity kept in a separate locked store | **Done** | Its own `identity` schema, researchers blocked by the database |

### The asset row — his 8 columns

This is a breakdown of the first line above, not eight extra requirements.

| His column | Us | Our column |
|---|---|---|
| patient fake ID | **Done** | `uploads.participant_id` |
| data type | **Done** | `upload_files.kind` |
| capture time | **Done** | `upload_files.captured_at` — new |
| session | **Done** | `upload_files.session_id` — new |
| size | **Done** | `bytes`, plus checksums |
| quality flags | **Done** | `quality_status` + `quality_flags` — new |
| device | Partly | `uploads.device_id` is empty on all Drive data |
| storage path | Partly | `object_key` holds a Drive ID, not a blob path |

### Data lake

| He asked for | Us | What we have |
|---|---|---|
| Auto-move old video to cheaper storage | **Done** | Hot → Cool at 30 days, Cool → Cold at 90. Nothing is ever deleted |
| ADLS Gen2 (folder-style storage) | Not built | Plain Blob storage. Must be recreated to change this, so do it before there is data |
| Folder layout `type/patient/session/…` | Not built | Comes with the upload path |
| Convert sensor data to Parquet | Not built | Still CSV inside the ZIP |

### Metadata catalog

| He asked for | Us | What we have |
|---|---|---|
| Structured data next to the catalog | **Done** | 9 research tables in the same database |
| Azure SQL, serverless | **Different** | PostgreSQL 16. Same job, and our whole backend already uses it. It does not pause when idle, so it costs a flat low-tens of dollars a month instead of near zero |
| Answer his question in one SQL query | Partly | The "within 2 hours of a dose" part now works. Two small gaps — see §3 |

### Identity and consent store

| He asked for | Us | What we have |
|---|---|---|
| Its own database or schema | **Done** | Own schema, one less thing to run |
| Almost nobody can read it | **Done** | Blocked in the database *and* in the API |
| Secrets in Key Vault | **Done** | DB password and both tokens live there; the app reads them with a managed identity |
| Consent: version, scope, time, withdrawal | Partly | All of it except **scope**. We need the ethics board to define the values — see §4 |
| Honour withdrawal and erasure | Partly | Withdrawal works and is provable. **Erasure cannot be run** — no routine exists yet |

### Ingestion

| He asked for | Us | What we have |
|---|---|---|
| Don't add Data Factory, Synapse or Databricks yet | **Done** | None of them. Just Container Apps, Postgres, Blob, Key Vault, logs |
| App uploads to storage via API or short-lived token | Not built | The route does not exist yet. This is the main missing piece |
| Upload triggers a function that writes the catalog row | Not built | Today it is a batch job that reads Drive |

### Researcher access

| He asked for | Us | What we have |
|---|---|---|
| Never storage keys, never identity | **Done** | Shared keys are switched off entirely, so none can be issued |
| Scoped read access through views | Partly | Three roles with real limits, but enforced in the API. No SQL views, so we cannot hand out a database connection |
| External researchers as Entra guests | Not built | Staff sign in with Firebase. Waiting on his question 2 |
| Access that expires by itself | Not built | Today someone flips a flag by hand |

### Governance from day one

| He asked for | Us | What we have |
|---|---|---|
| RBAC | **Done** | One managed identity, three narrow permissions, no stored passwords |
| Logging | **Done** | Azure logs, plus our own audit log of every staff read |
| Private networking | Not built | Storage, database and Key Vault still accept public traffic |
| Customer-managed keys | Not built | Microsoft-managed keys only |

### His suggested order of work

| He asked for | Us | What we have |
|---|---|---|
| Stand up storage, both databases, the catalog schema | **Done** | Done as two schemas in one database |
| Backfill the old Drive data | **Done** | Every Drive file became either a catalog row or a flagged problem row. It refuses to finish if the totals do not match, so nothing goes quietly missing |
| Then researcher access | **Done** | Read-only admin console, three roles |
| Write one ingestion function | Not built | Same work as the upload path above |

---

## 3. Open items

| # | What | How long |
|---|---|---|
| 1 | Make the API use the researcher database role for non-admin reads | Days |
| 2 | Add consent `scope` | Days, once the ethics board decides |
| 3 | Write the erasure routine: remove the identity, keep the anonymous study data | 1 week |
| 4 | Build the upload path, then the worker that catalogs each upload | 2–3 weeks |
| 5 | Build the nightly Drive-vs-database check | 1 week |
| 6 | Private networking and customer-managed keys | 1 week |
| 7 | Use drug codes instead of free text in `medication_logs` | Days |
| 8 | Add a walking-video file type | Days, after question 2 |
| 9 | External researcher access that expires by itself | After question 2 |

**Item 1 is the honest catch on the identity work.** The database now blocks a researcher connection
from reading identity, which is what Amos asked for and what an auditor can check. But our API still
connects as the owner, so until item 1 is done the live system is still relying on our own code.

**Item 5 blocks the rest.** We can only switch off the old Google Drive pipeline after 14 clean nights
of automatic checking, and that job is currently an empty placeholder.

---

## 4. Questions we need answered

1. **Are any patients or researchers in the EU?** (his question) We already picked Israel Central,
   which is EU-approved, so the region is fine either way. The answer changes what we must document.
2. **Do external researchers need the raw audio and video, or only numbers?** (his question) If only
   numbers, items 8 and 9 above get much simpler or disappear. If raw media leaves us, we should
   design for that now.
3. **What are the consent scope values?** (for the ethics board) The column is easy. Guessing the
   values in a medical consent record would be worse than leaving it out.

---

## Appendix — for the record

**What changed to get here.** Two migrations. `0006` moved the three identity tables into their own
schema, created a researcher role that cannot reach them, and added `captured_at`, `quality_status`,
`quality_flags` and `session_id` to `upload_files`. `0007` blocked one more table,
`participant_id_conflicts` — it looked like an operations queue but it lists Firebase user IDs, which
lead straight back to real identities. Both are safe to run twice; we ran the chain three times on a
throwaway database and the result was identical each time.

**Nothing broke for existing users.** No patient code was renumbered, no password re-keyed, no one
logged out, and the Google Drive pipeline was not touched. Moving a table between schemas does not
change the data or the app.

**Checked, not assumed.** We queried the database's own permission tables to confirm the researcher
role cannot read the identity schema, cannot read any column of the four blocked tables, can read
`age` and `medications` but not `signature_name` or `settings`, and can read the research tables.
Twelve checks, zero failures.

**Two known holes in the table links.** `events.session_id` and `participant_profiles.updated_by_device`
have no enforced link, so they can point at nothing. `events` is already full of historical rows, so
adding the rule now could fail the migration on data no one has checked yet.
