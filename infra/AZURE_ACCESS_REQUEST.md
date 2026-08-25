# Azure access request

Send this to whoever administers the Azure tenant. It lists everything the DopaX deployment needs
and nothing it doesn't, with the exact commands for each item.

The deployment itself is already written and validated (`infra/main.bicep`, `infra/deploy.sh`).
It is blocked purely on access.

**Current state.** `app@dopa-x.org` authenticates against tenant `5df9985a-1386-4f68-9374-2b5dd3c7a2c1`
and now has `Contributor` on subscription `58613d00-0629-4629-b103-934f7245ba71`
("Azure subscription 1", Enabled). With that we have already done everything Contributor permits:
the resource providers are registered (section 3) and `dopax-prod-rg` exists in Israel Central.

**What is left is one role assignment.** Contributor cannot create role assignments, and the
template creates three of them, so the deploy fails partway through without the grant in
section 2. Sections 4, 5, and 6 are confirmations rather than actions.

> **Before sending this: the compute platform is unresolved.** Azure Container Apps is not
> available in Israel Central, so the API, staff console, and both jobs cannot deploy as designed.
> This is our problem, not the tenant admin's, and it does not change the access being requested —
> but the resource table below will change once it is settled. See section 4 and
> `infra/README.md`. Requesting the section 2 grant now is still worthwhile, since it unblocks
> whatever the compute choice turns out to be.

---

## What is being deployed

A single resource group holding a REST API, an internal staff console, a PostgreSQL database, a
blob container for participant data, and a small build server that runs the deployments.
Everything is in **Israel Central**, deliberately — the study handles patient health data that has
to stay in-country.

| Resource | Type | SKU |
| --- | --- | --- |
| API + staff console | Container Apps | Consumption |
| Bootstrap + reconciler jobs | Container Apps Jobs | Consumption |
| Database | PostgreSQL Flexible Server | Burstable B1ms, 32 GB |
| Raw upload archive | Storage account, LRS | Hot → Cool → Cold lifecycle |
| Image registry | Container Registry | Basic |
| Secrets | Key Vault | Standard, RBAC |
| Logs | Log Analytics | Basic table plan, capped at 0.5 GB/day |
| Workload identity | User-assigned managed identity | — |
| Build server (Jenkins) | Linux VM + 64 GB Standard SSD | Standard_B2s |

No public blob access, no storage shared-key access, no registry admin user, TLS 1.2 minimum.
Workloads authenticate to storage, the registry, and Key Vault through the managed identity, so
there are no standing credentials in app configuration. The build server authenticates the same
way, through a system-assigned identity — see section 8.

---

## 1. A subscription — done

`58613d00-0629-4629-b103-934f7245ba71`, "Azure subscription 1", Enabled, tenant `dopa-x.org`.
`app@dopa-x.org` has `Contributor` on it and `az account show` succeeds.

One note for cost tracking and for scoping the HIPAA BAA in section 6: this is a shared
subscription rather than a dedicated one. A dedicated subscription would be cleaner for both, and
is worth considering before the resource group starts accruing spend, but it is not a blocker.

## 2. Role assignment — the one remaining ask

Grant `app@dopa-x.org` **Owner on `dopax-prod-rg`**, not Contributor. The resource group already
exists, so this is a single command:

```bash
az role assignment create \
  --assignee app@dopa-x.org \
  --role Owner \
  --scope /subscriptions/58613d00-0629-4629-b103-934f7245ba71/resourceGroups/dopax-prod-rg
```

**Contributor is not sufficient and the deployment will fail halfway through with it** — after the
database has already been provisioned, which is the expensive part to redo. The template creates
three role assignments to bind the managed identity to the registry (AcrPull), the storage account
(Storage Blob Data Contributor), and the vault (Key Vault Secrets User). Creating a role assignment
needs `Microsoft.Authorization/roleAssignments/write`, which Contributor explicitly excludes.

If Owner is too broad for your policy, the equivalent narrower pair is **Contributor + Role Based
Access Control Administrator**, both scoped to that resource group:

```bash
SCOPE=/subscriptions/58613d00-0629-4629-b103-934f7245ba71/resourceGroups/dopax-prod-rg

az role assignment create --assignee app@dopa-x.org --role Contributor --scope "$SCOPE"
az role assignment create --assignee app@dopa-x.org \
  --role "Role Based Access Control Administrator" --scope "$SCOPE"
```

The grant is scoped to one resource group either way. Nothing here needs subscription-level Owner.

## 3. Resource providers — done

Registered from our side. `*/register/action` turned out to be within Contributor, so this did not
need an admin after all. Nine of the ten report `Registered`:

`Microsoft.App`, `Microsoft.ContainerRegistry`, `Microsoft.DBforPostgreSQL`, `Microsoft.Storage`,
`Microsoft.KeyVault`, `Microsoft.ManagedIdentity`, `Microsoft.OperationalInsights`,
`Microsoft.Insights`, `Microsoft.Compute`.

`Microsoft.Network` is still `Registering`. It is much the largest of the ten and routinely takes
15–30 minutes rather than the usual two or three; no action is needed, but confirm it before the
first deploy:

```bash
az provider show -n Microsoft.Network --query registrationState -o tsv
```

The original commands are kept below for the record, and because a new subscription would need
them again.

```bash
for ns in Microsoft.App Microsoft.ContainerRegistry Microsoft.DBforPostgreSQL \
          Microsoft.Storage Microsoft.KeyVault Microsoft.ManagedIdentity \
          Microsoft.OperationalInsights Microsoft.Insights Microsoft.Network \
          Microsoft.Compute; do
  az provider register --namespace "$ns"
done
```

Registration is asynchronous and takes a few minutes. Verify with:

```bash
az provider list --query "[?namespace=='Microsoft.App'].registrationState" -o tsv
```

## 4. Israel Central — measured, with one blocker and one tight quota

**Policy: clear.** The subscription has zero policy assignments, so no "allowed locations" rule is
blocking `israelcentral`. Nothing needed here. Region is a data residency requirement rather than a
preference, so this was the item most likely to be fatal, and it is fine.

**Service availability: one blocker.** Checked per service against the provider manifests:

| Service | Israel Central |
| --- | --- |
| PostgreSQL Flexible Server | available |
| Storage, Container Registry, Key Vault, Log Analytics | available |
| Virtual Machines (build server) | available |
| App Service / Web App for Containers (Linux, B1–P1v3) | available |
| AKS, Container Instances | available |
| **Azure Container Apps** | **not available** |

Container Apps is not offered in Israel Central — not the environment, not `containerApps`, not
`jobs`. Confirmed both from the provider manifest and from Microsoft directly on
[azure-container-apps#1253](https://github.com/microsoft/azure-container-apps/issues/1253), where
the product team states the region is not on their expansion list. Verify current status with:

```bash
az provider show --namespace Microsoft.App \
  --query "resourceTypes[?resourceType=='managedEnvironments'].locations"
```

The nearest regions that do offer it are UAE North, Italy North, and Europe — all of which put
participant data outside the country, so none is acceptable. The compute platform has to change
instead; see `infra/README.md`.

**Quota: readable, and tighter than expected.** Now that `Microsoft.Compute` is registered:

| Quota | Current | Limit |
| --- | --- | --- |
| Total Regional vCPUs | 0 | **4** |
| Standard BS Family vCPUs | 0 | 4 |
| Standard Bsv2 Family vCPUs | 0 | 4 |

Four regional vCPUs is enough for the Standard_B2s build server (2 vCPUs) with 2 to spare, so the
original plan fits. It is *not* enough to absorb a move to AKS, which would need a raise here. Note
the limit is on regional vCPUs in total, so every VM-backed choice competes for the same four.

```bash
az vm list-usage --location israelcentral -o table
```

Quota increases go through a support request and take a day or two, so if the compute decision
lands on anything VM-backed, request the raise at the same time as the section 2 grant.

## 5. Policy exemptions that may be needed

No policy assignments were visible on the subscription at the scope we can read, so nothing here is
currently blocking. Still worth confirming against your policy set, since assignments inherited
from a management group may not be visible to us:

- **Public network access on PaaS.** The database, storage account, and vault currently use public
  endpoints restricted by firewall rules, with the database limited to the "Azure services only"
  sentinel range. If the tenant mandates private endpoints, tell us — it's a real design change
  (VNet-integrated compute) and we'd rather build it that way from the start than retrofit it.
- **Required tags.** We set `project`, `environment`, `dataClassification=phi`, and `managedBy`.
  If your policy requires others such as a cost centre or owner, send the list.
- **Key Vault purge protection is enabled and cannot be turned off.** That is intentional for PHI,
  but it means the vault survives for 90 days after any delete. Worth knowing before someone tries
  to tear down and immediately rebuild.

## 6. Compliance

The data is patient health data. The subscription needs to be covered by Microsoft's HIPAA BAA,
and Israel Central is chosen so it stays in-country. Please confirm the BAA covers subscription
`58613d00-0629-4629-b103-934f7245ba71`, and flag anything else your compliance process needs from
us.

This is the one place where the shared subscription noted in section 1 matters. If the BAA is
scoped per subscription, a dedicated one for DopaX is easier to attest than a shared one carrying
unrelated workloads.

## 7. Expected cost

Roughly **$60/month** for the platform itself — database, both apps, registry, logs, vault — and
about **$85/month all-in around month 12** once the upload archive is included.

The build server adds about **$45/month** on top: $35.04 for the Standard_B2s VM, $6.38 for the
64 GB Standard SSD holding the build history, and $3.65 for the static IP. Those three are checked
against Azure's public retail pricing API for Israel Central rather than estimated.

Storage is the only line that grows without bound, because study data is retained indefinitely.
These figures assume around 0.4 GB per uploading participant-day at 60% adherence, roughly
**300 GB per month** at 43 participants. That assumption is an estimate, not a measurement: the
legacy Google Drive corpus has never been inventoried, and the figure recorded in our migration
plan (1–2 GB) is a ceiling observed on the heaviest days rather than an average. If the true mean
turns out to be the ceiling, the month-12 figure is closer to $156/month. We are measuring this
before it matters for budget.

One regional caveat worth pricing in: Israel Central has no Archive blob tier, so Cold LRS at
$0.0045/GB-month is the cheapest floor available. Sweden Central offers Archive at $0.00099, which
would cut the storage line by around 40%, but that would put participant data outside the country.

A budget alert on the resource group would be sensible. Full workings, including a region-by-region
comparison and projections to 20,000 participants, are in `infra/DopaX-Azure-cost-model.pdf`.

## 8. CI/CD — already covered above, no extra permission needed

Deployments run from Jenkins on the VM in the table above, rather than from a hosted CI service.
Two consequences worth knowing:

- **No app registration, and no stored credential anywhere.** The VM gets a system-assigned managed
  identity and the pipeline authenticates with `az login --identity`. There is no client secret and
  no federated credential to create, rotate, or leak.
- **Nothing for you to do beyond section 2.** That identity needs `AcrPush` on the registry,
  `Key Vault Secrets User` on the vault, and `Contributor` on the resource group. All three are
  scoped inside `dopax-prod-rg`, so the Owner grant in section 2 is enough for me to create them.

The only thing this adds to your side is the B-series vCore quota in section 4, which the current
limit of 4 regional vCPUs already covers. `Microsoft.Compute` is registered.

---

## How to verify it worked

Once the section 2 grant is in place, this proves the access side is complete:

```bash
az login
az account set --subscription 58613d00-0629-4629-b103-934f7245ba71

az role assignment list --assignee app@dopa-x.org \
  --scope /subscriptions/58613d00-0629-4629-b103-934f7245ba71/resourceGroups/dopax-prod-rg \
  -o table
```

`./infra/deploy.sh --what-if` is the fuller check — it writes nothing and lists exactly what would
be created — but it will not pass until the Container Apps problem in section 4 is resolved, because
the template targets a resource type that does not exist in this region.

---

## Status summary

| Item | State |
| --- | --- |
| 1. Subscription | done — `58613d00-0629-4629-b103-934f7245ba71` |
| 2. Role assignment | **waiting on tenant admin** |
| 3. Resource providers | done — 9 of 10 registered, `Microsoft.Network` still in progress |
| 4. Region policy | done — no assignments blocking `israelcentral` |
| 4. Region quota | done — 4 regional vCPUs, sufficient as designed |
| 4. Container Apps in region | **blocked — unavailable, our redesign to do** |
| 5. Policy exemptions | confirm inherited management-group policy |
| 6. HIPAA BAA | confirm coverage of this subscription |
