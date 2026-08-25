#!/usr/bin/env python3
"""
Three ways to host this, priced line by line so every number is a visible
multiplication. All unit prices verified against the Azure Retail Prices API
for israelcentral on 2026-08-17 (see azure_unit_prices.py to re-check).

    python3 scratch/azure_hosting_options.py
"""

HOURS = 730          # billed hours in an average month
SPM = 730 * 3600     # billed seconds in an average month
DPM = 30.4

# --- verified unit prices, Israel Central ----------------------------------
VM_B2S = 0.048           # per hour, 2 vCPU / 4 GB Linux VM
VM_B1MS = 0.024          # per hour, 1 vCPU / 2 GB
PG_B1MS = 0.022          # per hour, managed Postgres 1 vCPU / 2 GB
PG_B2S = 0.088           # per hour, managed Postgres 2 vCPU / 4 GB
PG_GP_VCORE = 0.1085     # per vCore-hour, General Purpose
PG_DISK = 0.164          # per GB PROVISIONED per month
DISK_E10 = 11.52         # 128 GB standard SSD, flat per month
PUBLIC_IP = 0.0036       # per hour, standard static IPv4
CA_VCPU_ON = 0.000034    # per vCPU-second, request-serving
CA_VCPU_IDLE = 0.000004  # per vCPU-second, warm but idle
CA_MEM = 0.000004        # per GiB-second
LOGS_ANALYTICS = 3.29    # per GB ingested, Analytics tier
LOGS_BASIC = 0.66        # per GB ingested, Basic tier
ACR_BASIC = 0.1666       # per day
KEYVAULT = 1.00          # per month, rounded
EGRESS = 0.087           # per GB leaving Azure

N = 43                   # participants today


def line(label, detail, cost):
    return (label, detail, cost)


def show(title, rows, caveats):
    total = sum(c for _, _, c in rows)
    print(f"\n{'=' * 86}\n{title}\n{'=' * 86}")
    for label, detail, cost in rows:
        print(f"  {label:<26}{detail:<40}{'$%.2f' % cost:>10}")
    print(f"  {'':<26}{'FIXED TOTAL PER MONTH':<40}{'$%.2f' % total:>10}")
    for c in caveats:
        print(f"    ! {c}")
    return total


# --- Option 1: one VM running everything in Docker Compose -----------------
a = show(
    "OPTION 1  One Linux VM, Docker Compose, Postgres in a container",
    [
        line("Virtual machine", f"B2s 2vCPU/4GB: {HOURS}h x ${VM_B2S}", VM_B2S * HOURS),
        line("OS + data disk", "E10 128GB SSD, flat monthly", DISK_E10),
        line("Static public IP", f"{HOURS}h x ${PUBLIC_IP}", PUBLIC_IP * HOURS),
        line("Logs", "journald on the local disk", 0.0),
        line("Container registry", "build on the box / Docker Hub", 0.0),
        line("Secrets", "env file on the box", 0.0),
    ],
    [
        "You patch the OS, you own the backups, you restore it at 3am.",
        "Postgres in a container on one disk = one bad disk from data loss.",
        "No point-in-time restore unless you build it. 43 patients of medical data.",
        "Deploy = ssh. No rollback, no health-gated release.",
    ])

# --- Option 2: managed, right-sized for 43 participants --------------------
api = (CA_VCPU_ON * SPM * 0.10 + CA_VCPU_IDLE * SPM * 0.90) * 0.5 + CA_MEM * SPM * 1
ingest = (N * DPM) * 240 * (2 * CA_VCPU_ON + 4 * CA_MEM)
admin = (CA_VCPU_ON * SPM * 0.05 + CA_VCPU_IDLE * SPM * 0.95) * 0.5 + CA_MEM * SPM * 1
grant = min(180_000 * CA_VCPU_ON + 360_000 * CA_MEM, api + ingest + admin)
b = show(
    "OPTION 2  Managed services, right-sized (what I should have published)",
    [
        line("PostgreSQL", f"B1ms 1vCPU/2GB: {HOURS}h x ${PG_B1MS}", PG_B1MS * HOURS),
        line("PostgreSQL disk", f"64 GB provisioned x ${PG_DISK}", 64 * PG_DISK),
        line("API container", "0.5 vCPU/1GB, 10% active, scales down", api),
        line("Admin container", "0.5 vCPU/1GB, 5% active", admin),
        line("Ingestion job", f"{N * DPM:,.0f} runs x 240s x 2vCPU/4GB", ingest),
        line("Free grant", "180k vCPU-s + 360k GiB-s included", -grant),
        line("Logs", f"4 GB x ${LOGS_BASIC} Basic tier", 4 * LOGS_BASIC),
        line("Container registry", f"Basic, {DPM:.0f} days x ${ACR_BASIC}", ACR_BASIC * DPM),
        line("Key Vault", "secrets + rotation", KEYVAULT),
    ],
    [
        "Managed backups with point-in-time restore are included.",
        "Deploys are health-gated with automatic rollback.",
        "Scales without a rebuild when enrolment grows.",
    ])

# --- Option 3: what the PDF actually says ---------------------------------
api3 = (CA_VCPU_ON * SPM * 0.10 + CA_VCPU_IDLE * SPM * 0.90) * 0.5 + CA_MEM * SPM * 1
c = show(
    "OPTION 3  What I published in the PDF",
    [
        line("PostgreSQL", f"B2s 2vCPU/4GB: {HOURS}h x ${PG_B2S}", PG_B2S * HOURS),
        line("PostgreSQL disk", f"64 GB provisioned x ${PG_DISK}", 64 * PG_DISK),
        line("Containers", "API + admin + ingest + reconcile", api3 + admin + ingest - grant),
        line("Logs", f"4 GB x ${LOGS_ANALYTICS} Analytics tier", 4 * LOGS_ANALYTICS),
        line("Container registry", f"Basic, {DPM:.0f} days x ${ACR_BASIC}", ACR_BASIC * DPM),
        line("Key Vault", "secrets + rotation", KEYVAULT),
    ],
    ["Oversized database and the expensive log tier, for no benefit at 43 people."])

print(f"\n{'=' * 86}\nFIXED COST, 43 PARTICIPANTS\n{'=' * 86}")
print(f"  One VM, do-it-yourself         ${a:>7.2f}/mo   ${a * 12:>8,.0f}/yr")
print(f"  Managed, right-sized           ${b:>7.2f}/mo   ${b * 12:>8,.0f}/yr"
      f"   (+${b - a:.2f}/mo over the VM)")
print(f"  What the PDF says              ${c:>7.2f}/mo   ${c * 12:>8,.0f}/yr")
print(f"\n  Right-sizing saves ${c - b:.2f}/mo ({(1 - b / c) * 100:.0f}%) with no loss of capability.")
print(f"  The managed premium over a bare VM is ${b - a:.2f}/mo — that buys backups,")
print("  point-in-time restore, health-gated deploys, and nobody patching a server.")

print(f"\n{'=' * 86}\nWHAT IS NOT IN ANY OF THESE (and should be)\n{'=' * 86}")
print(f"  Egress is ${EGRESS}/GB. Researchers pulling ZIPs out is billable:")
for gb in (50, 200, 1000):
    print(f"     {gb:>5} GB downloaded/month  ->  ${gb * EGRESS:>7.2f}/mo")
print("  Postgres backup storage beyond the free allowance is $0.105/GB/month.")
print("  Uploads INTO Azure are free, so device traffic costs nothing.")
