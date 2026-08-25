# Deploying DopaX to Azure

Israel Central. Azure Container Apps for the API, the staff console, and every
worker; PostgreSQL Flexible Server as the system of record; Blob Storage for the
raw ZIP archive.

Cost analysis and the reasoning behind each service choice live in the
`azure-hosting-plan` canvas. This document is the runbook.

> **This template cannot deploy as written. Container Apps is not available in
> Israel Central.** Not the environment, not `containerApps`, not `jobs` —
> confirmed against the provider manifest and by the product team on
> [azure-container-apps#1253](https://github.com/microsoft/azure-container-apps/issues/1253),
> which states the region is not on their expansion list. Everything else in the
> stack is available in-region; only compute has to change. Region is fixed by
> data residency, so moving the region is not the fix. See
> "Choosing replacement compute" below. Every `az containerapp` command in this
> runbook is provisional until that decision lands.

## Prerequisites

```bash
brew install azure-cli        # 2.89 or later
az login
az account set --subscription "<your subscription>"
```

Docker must be running locally, and Node 22 or later — both `backend` and `admin`
declare `"node": ">=22"`, and the Azure MCP server needs it too.

You need `Contributor` plus `User Access Administrator` on the subscription, or
`Owner` on the resource group — the template creates role assignments, which
plain `Contributor` cannot do.

If you do not administer the Azure account yourself, `AZURE_ACCESS_REQUEST.md`
in this directory is a ready-to-forward request covering the subscription, roles,
resource providers, Israel Central quota, policy exemptions, and expected cost.
`AZURE_ACCESS_REQUEST.he.md` is the same request in Hebrew.

### Behind a corporate proxy

If your shell sets `http_proxy` and `https_proxy`, two things will break the
deploy in ways that are easy to misread.

`no_proxy` has to exclude the Azure endpoints, or registry and blob traffic gets
routed through the proxy and either stalls or fails TLS verification:

```bash
export no_proxy="169.254.169.254,.azurecr.io,.blob.core.windows.net,.vault.azure.net,.azurecontainerapps.io"
```

Separately, **the Docker daemon does not read your shell environment.** `docker
push` to the registry goes through Docker Desktop's own proxy settings, under
Settings → Resources → Proxies, and if the proxy does TLS interception its root
CA also has to be trusted there. A misconfigured daemon proxy shows up as a push
that hangs at "Retrying in N seconds" rather than as an obvious proxy error.

## First deployment

```bash
./infra/deploy.sh
```

Roughly 15 minutes, most of it waiting on PostgreSQL. The script is idempotent;
run it again any time.

It runs in two passes on purpose. A container app cannot be created pointing at
an image tag that does not exist yet, so pass one creates the registry and
everything around it, images are built and pushed, and pass two creates the apps.
That is what the `deployApplications` parameter controls.

Preview changes without applying them:

```bash
./infra/deploy.sh --what-if
```

## What gets created

Phase 1 (`./infra/deploy.sh`) creates the data layer and the build server:

| Resource | Name | SKU | Notes |
| --- | --- | --- | --- |
| PostgreSQL Flexible Server | `dopax-prod-pg-*` | Burstable B1ms, PG 16 | 32 GB, 35-day backups |
| Storage account | `dopaxprod*` | Standard LRS | Versioning + 30-day soft delete |
| Container Registry | `dopaxprod*` | Basic | Managed-identity pulls, no admin user |
| Key Vault (application) | `dopax-prod-kv-*` | Standard | Database URL and both JWT secrets |
| Key Vault (CI) | `dopax-prod-ci-*` | Standard | Jenkins admin password only |
| Log Analytics | `dopax-prod-logs` | Basic table plan | Capped at 0.5 GB/day |
| Managed identity (workload) | `dopax-prod-id` | User-assigned | Pulls images, reads secrets, writes blobs |
| Managed identity (CI) | `dopax-prod-ci-id` | User-assigned | Registry Contributor, CI vault only |
| Build server VM | `dopax-prod-ci` | Standard_B2ls_v2, Ubuntu 24.04 | Jenkins + Caddy, 64 GB StandardSSD |
| VNet + NSG + public IP | `dopax-prod-ci-*` | Static IP | 443 and 22 from the allowlist only |

Phase 2 (`--with-apps`) adds the App Service plan, the API, and the staff
console. Container Apps is not available in Israel Central, which is why the
application layer is App Service rather than the usual Container Apps setup.

The two managed identities are deliberately separate. The build server can push
images to the registry but has no access policy on the application Key Vault, so
a compromised build agent cannot read `jwt-secret` or the database URL.

Around $60/month at study scale before object storage, or roughly $85/month
all-in at month 12. The archive is the only part that grows without bound.

Three choices in the template are what keep that number down, and each is a
parameter you can reverse:

- `postgresSku` is B1ms, not B2s. Raw ZIPs live in blob storage, so the database
  holds metadata only — about 30 rows per participant-day. B2s costs 4× for
  headroom nothing is asking for yet.
- `useBasicLogTier` puts container console logs on the Basic plan at $0.66/GB
  instead of $3.29/GB Analytics. The trade-off is no alert rules and a reduced
  KQL surface over app logs.
- `apiAlwaysWarm` keeps one API replica alive. Container Apps bills allocated
  capacity per second rather than per request, so this costs about $20/month at
  zero traffic and roughly $10 of that is the memory reservation alone. It stays
  on anyway: a cold start in front of a phone uploading on cellular is worth
  more than the ~$14 it would save. The staff console does scale to zero.

Storage projections assume about 0.4 GB per uploading participant-day at 60%
adherence. **That is an estimate, not a measurement.** The 1–2 GB figure in
`backend/docs/MIGRATION_PLAN.md` §2.3 is a ceiling on the heaviest days, and the
legacy Drive folder has never been inventoried, so nobody knows the real mean
yet. Inventorying it is the cheapest way to remove the largest error in the cost
model. See `infra/DopaX-Azure-cost-model.pdf` for the full workings and
`scratch/azure_unit_prices.py` to re-verify any unit price against the live
pricing API.

Nothing in the template stores a password in application configuration. The
apps authenticate to the registry, Key Vault, and Blob Storage with the
user-assigned managed identity.

### The lifecycle policy is the main cost control

Uploads move Hot to Cool at 30 days and Cool to Cold at 90. Israel Central has
no Archive tier, so Cold at $0.0045/GB-month is the floor. Without this rule the
same archive costs about 3.3× more by month 24.

**There is no delete action anywhere in the policy, deliberately.** Tiering is a
cost control, not a retention policy. Study data is kept indefinitely.

## The build server

Jenkins runs on a small VM behind Caddy, reachable only from the addresses in
the NSG allowlist. `deploy.sh` detects your public IP and allowlists it; add
others with `DOPAX_ALLOWED_IPS='1.2.3.4/32,5.6.7.8/32'` and rerun.

```bash
# URL
https://dopax-prod-ci-<suffix>.israelcentral.cloudapp.azure.com/

# Password (username is admin)
az keyvault secret show --vault-name dopax-prod-ci-<suffix> \
  --name jenkins-admin-password --query value -o tsv
```

Configuration is code. `infra/cloud-init/jenkins.yaml` is the only place the
security realm, plugin set, and system settings are defined, and JCasC reverts
overlapping UI edits on reload. `customData` is immutable after creation, so
**changing cloud-init means deleting and recreating the VM** — editing the file
and rerunning `deploy.sh` alone changes nothing on a VM that already exists.

Pipelines authenticate with `az login --identity`. There is no service principal
secret on the machine. Images are built with `az acr build`, server-side, so the
VM needs no Docker daemon and does no cross-compilation.

### If the VM comes up but nothing answers

`cloud-init status --long` reports the outcome and
`/var/log/dopax-bootstrap.log` has the detail. When SSH is refused, get on the
box without it:

```bash
az vm run-command invoke -g dopax-prod-rg -n dopax-prod-ci \
  --command-id RunShellScript --query "value[0].message" -o tsv \
  --scripts 'cloud-init status --long; tail -40 /var/log/dopax-bootstrap.log'
```

Three failure modes have already been hit and fixed in cloud-init. They are
recorded because each one presents as something other than its cause:

- **`kex_exchange_identification: Connection closed`.** `/run/sshd` was missing,
  so socket-activated sshd exited the moment a connection arrived. It reads like
  a network or host-key problem and is neither. Fixed by a tmpfiles rule.
- **`NO_PUBKEY 7198F4B714ABFC68`.** Jenkins rotates its apt signing key under a
  year-stamped filename. The old key is still served, so the URL keeps working
  while the signature stops matching. The fingerprint is now pinned and verified,
  and a future rotation fails with a message that says so.
- **Jenkins exits 5 immediately after install.** A JCasC block that names an
  attribute or plugin that does not exist is fatal, not ignored. Both
  `excludeClientIPFromCrumb` and a `queueItemAuthenticator` without the
  `authorize-project` plugin will stop Jenkins from booting at all.

### If the console is unreachable from your network

The allowlist is only half the story. Some corporate networks complete the TCP
handshake themselves and then blackhole the traffic, which looks identical to a
firewall problem on the Azure side. Two checks separate them:

```bash
# 1. A port the NSG denies should NOT connect. If port 80 "succeeds",
#    something local is answering on the server's behalf.
nc -z -w 6 <public-ip> 80

# 2. A real Caddy endpoint returns a certificate.
openssl s_client -connect <public-ip>:443 -servername <fqdn> </dev/null 2>&1 \
  | grep -E "peer certificate|handshake has read"
```

`no peer certificate available` together with `handshake has read 0 bytes` means
the ClientHello left and nothing came back: the VM never saw it. Confirm the
server side independently with `run-command` — `curl -sk --resolve <fqdn>:443:127.0.0.1
https://<fqdn>/login` from the VM returns 200 when Jenkins is healthy — and then
connect from a network that permits direct egress, remembering to allowlist that
new IP.

## After the first deployment

### 1. Run the R5 bootstrap, and watch it

`/readyz` reports `bootstrap: pending` until the historical import has run. This
is a deliberate, observed step, not something the deploy script does for you: a
Drive backfill takes hours, and guardrail R5 requires a failed step to abort the
run rather than leave a half-migrated database looking finished.

```bash
RG=dopax-prod-rg
az containerapp job start -g $RG -n dopax-prod-bootstrap

# Watch it
az containerapp job execution list -g $RG -n dopax-prod-bootstrap -o table
az containerapp logs show -g $RG -n dopax-prod-bootstrap --follow
```

It takes an advisory lock, records completed steps in `migration_steps`, and is
safe to run twice. A crash resumes at the failed step.

### 2. Grant staff access

The console refuses everyone who is not in `staff_users`. There is no
self-registration.

```bash
cd backend
npm run staff:add -- --email you@example.com --role admin --name "Your Name"
```

### 3. Verify

```bash
API=$(az deployment group show -g $RG -n main --query properties.outputs.apiUrl.value -o tsv)
curl $API/healthz     # {"status":"ok"}
curl $API/readyz      # bootstrap: complete
curl $API/v1/config   # bothArch: true
```

`bothArch` must read `true`. Guardrail R3 keeps the legacy Drive pipeline
authoritative until 14 consecutive clean reconciliation runs.

## CI/CD

Production deploys run from Jenkins on `dopax-prod-ci`, not from GitHub Actions.
The job **Deploy server** (`dopax-deploy`) checks out this repository, builds
images with `az acr build`, and applies `infra/apps.bicep`. It authenticates
with `az login --identity`. It never applies `main.bicep`, so it never needs
`JWT_SECRET` or the PostgreSQL admin password, and it does not start the R5
bootstrap.

After the VM is up, install the job (idempotent) and add the printed deploy
key to `covivi243/dopax-mobile` as a read-only GitHub deploy key. Then open
Jenkins and run **Deploy server**.

`.github/workflows/deploy.yml` still runs lint, typecheck, and tests on pull
requests. It does not deploy.

The CI identity is **Website Contributor**, **Web Plan Contributor**, and
**Monitoring Contributor** on the resource group, plus **Contributor** on the
registry. It has no access policy on the application Key Vault. Rotating
`JWT_SECRET` still signs every participant out, which guardrail R1 forbids.

## Choosing replacement compute

Measured against the provider manifests for `israelcentral`, so this is what is
actually offered rather than what the docs pages imply. PostgreSQL Flexible
Server, Storage, Container Registry, Key Vault, Log Analytics, and Virtual
Machines are all available in-region and unaffected. The choice is only about
where the API, the staff console, and the two jobs run.

| Option | In region | Notes |
| --- | --- | --- |
| App Service / Web App for Containers | yes, B1 through P1v3 Linux | Closest fit. Managed TLS and custom domains, managed identity, deployment slots in place of revisions, pulls the same images from ACR. No scale-to-zero, so the staff console stops being free when idle. |
| Container Instances | yes | No ingress, no load balancing, no revisions. Plausible for the two jobs, not for a public API. |
| AKS | yes | Closest to Container Apps semantically, and the path the upstream issue reporter took. Far more operational surface than a 43-participant study warrants, and it needs a quota raise — see below. |

The regional vCPU limit is **4**, and it is a total across the region rather than
per family. The Standard_B2ls_v2 build server takes 2 of those, leaving 2. App
Service plans bill against their own quota rather than regional vCPUs, so that
option fits inside the current limit; AKS does not and would need a support
request first.

Two things do not have a like-for-like replacement and need deciding explicitly:

- **Cron.** Container Apps Jobs is what currently schedules the reconciler at
  02:30 UTC and runs the R5 bootstrap. On App Service the equivalents are
  WebJobs or a timer-triggered Function on the same plan. This is also the point
  at which the unused `pg-boss` dependency below stops being dead weight and
  becomes a real option.
- **Scale-to-zero for the staff console.** The cost model assumes it costs
  nothing when idle. On App Service it shares the API's plan and costs nothing
  extra, which happens to land in the same place by a different route — but the
  `apiAlwaysWarm` reasoning in the cost section above no longer applies as
  written, because App Service is always warm by construction.

Both `postgresSku` and the storage lifecycle policy are unaffected, so the
database and archive lines of the cost model still hold. The compute line needs
recomputing once the option is chosen; `scratch/azure_unit_prices.py` re-verifies
any unit price against the live pricing API.

## Known gaps

These are real and this deployment does not hide them.

- **Container Apps is unavailable in Israel Central**, so `main.bicep` cannot
  deploy as written. This is the blocker ahead of everything else in this list,
  and it is an architecture decision rather than a fix — see above.
- **No storage adapter exists.** `src/storage/` is absent even though
  `src/config/env.ts` validates `STORAGE_BACKEND=azure`. The infrastructure is
  provisioned and the identity has `Storage Blob Data Contributor`, but nothing
  writes to the container yet. The template also passes `AZURE_STORAGE_ACCOUNT`
  and `AZURE_CLIENT_ID` for a managed-identity client, while the env schema
  currently requires `AZURE_STORAGE_CONNECTION_STRING`. The schema should move
  to managed identity rather than the deployment moving to a connection string.
- **The reconciler job runs a placeholder.** It is scheduled at 02:30 UTC so the
  schedule is reviewable now, but the entrypoint does not exist. The 14-day
  clean-run count toward `BOTH_ARCH=false` cannot start until it is real.
- **`pg-boss` is installed and never imported.** Either wire it or drop it.
  Container Apps Jobs already covers cron scheduling.

## Hardening backlog

Ordered by how much they matter for participant data.

1. **VNet-integrate the database.** PostgreSQL is currently reachable from Azure
   services via the `0.0.0.0` sentinel firewall rule, which is the narrowest
   option without a VNet. Moving the Container Apps environment onto an
   infrastructure subnet and the database behind a private endpoint removes
   public reachability entirely. This is the single biggest remaining exposure.
2. **Restrict Blob and Key Vault to the same VNet** once it exists.
3. **Sign the HIPAA BAA** with Microsoft. Every service here is in scope at no
   extra cost. Note that Firebase Auth stays with Google under guardrail R1 and
   is not covered by it.
4. **Enable zone-redundant HA** once confirmed available in Israel Central. Set
   `postgresHighAvailability=true`; it doubles the database bill.
5. **Consider a private endpoint for the registry** (requires Premium).

## Rollback

Revisions are immutable, so rolling back is repointing traffic:

```bash
az containerapp revision list -g $RG -n dopax-prod-api -o table
az containerapp ingress traffic set -g $RG -n dopax-prod-api \
  --revision-weight <previous-revision>=100
```

Rolling the application back does **not** roll back a database migration.
Migrations are additive by design; verify before assuming a schema change is
reversible.

## Connecting the Azure MCP server

`.cursor/mcp.json` registers Microsoft's `@azure/mcp` server. It authenticates
through `DefaultAzureCredential`, which picks up your `az login` session, so
sign in first and then reload the Cursor window.
