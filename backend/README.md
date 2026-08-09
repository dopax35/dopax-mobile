# DopaX Backend

Node.js + PostgreSQL system of record for the DopaX / PDCollect research platform.

Read [`docs/MIGRATION_PLAN.md`](docs/MIGRATION_PLAN.md) first — it explains why this service
exists, what it replaces, and the four requirements every design choice traces back to.

## What this replaces

Research data currently flows from the mobile apps as daily ZIPs through a hardcoded Google Apps
Script into a single Google Drive folder. There is no server, no query layer, and no way to see
what participants are doing until their uploads stop arriving.

This service adds a real backend *alongside* that pipeline. It does not switch it off. The legacy
path keeps running until reconciliation proves the new one is complete.

## Requirements

- **Node 22 LTS or newer.** Node 18 is end-of-life and below Fastify 5's minimum.
- **Docker Desktop** running, for the local Postgres and MinIO stack.

## Quick start

```bash
cp .env.example .env
echo "JWT_SECRET=$(openssl rand -base64 48)" >> .env

npm install
npm run stack:up              # Postgres :55432, MinIO :9000, Adminer :8081
npm run db:migrate
npm run dev                   # API on :8080
```

Postgres is published on **55432, not 5432**, because a native Postgres already holds
`127.0.0.1:5432` on this machine. Docker binds the wildcard address, so the native instance wins
for `localhost` and the app would silently connect to the wrong database.

### If `npm install` hangs

`~/.npmrc` points npm at the Amdocs corporate proxy (`genproxy.amdocs.com:8080`), which does not
resolve when you are off the VPN — npm hangs indefinitely instead of failing. The shell also
exports `http_proxy`/`https_proxy` without a `http://` scheme, which npm rejects. Bypass both:

```bash
env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
  npm install --userconfig ./.npmrc
```

Verify:

```bash
curl localhost:8080/healthz
curl localhost:8080/readyz
curl localhost:8080/v1/config
```

## The `BOTH_ARCH` switch

The single most important setting. See MIGRATION_PLAN.md §4.2.

| Value | Meaning |
|---|---|
| `true` (default) | Legacy Google Drive pipeline is authoritative. This backend runs in parallel and is reconciled against Drive nightly. Clients dual-write. |
| `false` | This backend is the source of truth. Clients stop dual-writing. |

Flipping to `false` requires 14 consecutive clean reconciliation runs. The flip is reversible, and
nothing on Drive is ever mutated or deleted.

**The rule that governs dual-run: the legacy path must never be made worse.** Clients keep separate
`.uploaded` (legacy) and `.uploaded_v2` (backend) markers with independent retry schedules, so an
outage here cannot block a legacy upload or delay on-device retention cleanup.

## Storage backends

`STORAGE_BACKEND` selects where raw ZIPs live.

| Value | Use |
|---|---|
| `gdrive` | **Default for laptop development.** Raw ZIPs stay on Google Drive and are stream-parsed; only the parsed rows land in Postgres. The corpus is far larger than a laptop disk, so we never copy it down. |
| `minio` | Local S3-compatible storage from `docker-compose.yml`. |
| `s3` | AWS S3, Cloudflare R2, or any S3-compatible target. |
| `azure` | Azure Blob Storage. |

Production hosting is deliberately undecided (Azure / AWS / Railway). Nothing in this codebase is
cloud-specific apart from the storage adapter: the job queue runs inside Postgres via pg-boss, and
there is no TimescaleDB dependency, so plain managed Postgres 16 works everywhere.

## Testing from a physical phone

`localhost` is not reachable from a device. Find the laptop's LAN address:

```bash
ipconfig getifaddr en0        # → e.g. 192.168.1.42, so the API base is http://192.168.1.42:8080
```

- **Android emulator** reaches the host at `10.0.2.2`.
- **Physical Android** needs a debug-only `network_security_config.xml` allowing cleartext to that
  IP. The release config stays HTTPS-only.
- **iOS Simulator** reaches `localhost` directly.
- **Physical iPhone** needs a debug-only `NSAllowsLocalNetworking` ATS exception, plus the
  local-network permission prompt on iOS 14+.
- Simplest alternative: `cloudflared tunnel --url http://localhost:8080` gives a real HTTPS URL and
  avoids both ATS and cleartext configuration entirely.

The server binds `0.0.0.0` so LAN access works without further changes.

## Layout

```
src/
  config/      Zod-validated environment, fails loudly at boot
  db/
    schema/    Drizzle table definitions
    migrations/ Generated SQL, applied by npm run db:migrate
  routes/      HTTP surface
  auth/        Firebase ID token verification, participant resolution
  storage/     StorageAdapter implementations
  domain/      Ingestion, reconciliation, exports
  workers/     pg-boss job handlers
tests/
docs/
scripts/
```

## Secrets

`.env`, `secrets/`, and local `pg_dump` output are git-ignored. Two service account keys go in
`secrets/`:

- a Google service account with **read access to the Drive folder** — note the folder must be
  explicitly shared with the service account's email address, or it sees nothing
- a Firebase Admin key, for the Firestore export and ID token verification

Nothing about authentication changes for existing users. Firebase remains the identity provider
and this service only *verifies* tokens; no credential is ever migrated.
