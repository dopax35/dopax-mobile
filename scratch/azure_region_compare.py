#!/usr/bin/env python3
"""
Region-by-region price comparison for the DopaX stack, straight from the public
Azure Retail Prices API (no auth). Answers one question: what does moving out of
Israel Central actually save, and which region is genuinely cheapest?

Prices the four lines that dominate the bill:
  - PostgreSQL Flexible Server B1ms compute (per hour)
  - Container Apps vCPU + memory (per second, active)
  - Blob Hot / Cool / Cold storage (per GB-month)
  - A Standard_B2s Linux VM for the Jenkins controller (per hour)

    python3 scratch/azure_region_compare.py
"""

import json
import urllib.parse
import urllib.request

BASE = "https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview"

REGIONS = [
    "israelcentral",
    "swedencentral",
    "northeurope",
    "westeurope",
    "polandcentral",
    "uksouth",
    "eastus",
    "centralus",
    "southcentralus",
    "westus2",
]

HOURS = 730


def fetch(flt):
    url = f"{BASE}&$filter={urllib.parse.quote(flt)}"
    items, pages = [], 0
    while url and pages < 8:
        with urllib.request.urlopen(url, timeout=60) as r:
            data = json.load(r)
        items += data.get("Items", [])
        url = data.get("NextPageLink")
        pages += 1
    return items


def consumption(items):
    for i in items:
        if i["type"] != "Consumption" or i["unitPrice"] == 0:
            continue
        name = i["meterName"].lower()
        if "spot" in name or "low priority" in name:
            continue
        yield i


def first_price(items, must, must_not=()):
    """Cheapest consumption price whose meter name contains every `must` token."""
    best = None
    for i in consumption(items):
        name = i["meterName"].lower()
        if not all(t in name for t in must):
            continue
        if any(t in name for t in must_not):
            continue
        if best is None or i["unitPrice"] < best:
            best = i["unitPrice"]
    return best


def region_prices(region):
    out = {}

    pg = fetch(f"armRegionName eq '{region}' and serviceName eq 'Azure Database for PostgreSQL'")
    out["pg_b1ms_hr"] = first_price(pg, ["b1ms"])

    aca = fetch(f"armRegionName eq '{region}' and serviceName eq 'Azure Container Apps'")
    out["aca_vcpu_s"] = first_price(aca, ["active", "vcpu"])
    out["aca_mem_s"] = first_price(aca, ["active", "memory"])

    # skuName here is the tier + redundancy ('Hot LRS', 'Cold LRS'), not 'Standard LRS'.
    blob = fetch(
        f"armRegionName eq '{region}' and serviceName eq 'Storage' "
        "and productName eq 'General Block Blob v2'"
    )
    lrs = [i for i in blob if i.get("skuName", "").endswith("LRS")]
    out["blob_hot_gb"] = first_price(lrs, ["hot", "data stored"])
    out["blob_cool_gb"] = first_price(lrs, ["cool", "data stored"])
    out["blob_cold_gb"] = first_price(lrs, ["cold", "data stored"])
    out["blob_archive_gb"] = first_price(lrs, ["archive", "data stored"])

    vm = fetch(
        f"armRegionName eq '{region}' and serviceName eq 'Virtual Machines' "
        "and armSkuName eq 'Standard_B2s'"
    )
    out["vm_b2s_hr"] = first_price(vm, ["b2s"], must_not=["windows"])

    return out


def fmt(v, scale=1.0, digits=2):
    return "n/a" if v is None else f"{v * scale:,.{digits}f}"


def main():
    rows = {}
    for r in REGIONS:
        print(f"fetching {r} ...")
        rows[r] = region_prices(r)

    # Monthly cost of the current design: B1ms Postgres, one warm 0.5 vCPU / 1 GiB
    # API replica, a Jenkins B2s VM, and 300 GB sitting on Cold.
    print()
    header = (
        f"{'region':<16}{'PG B1ms':>10}{'ACA warm':>10}{'B2s VM':>10}"
        f"{'300GB cold':>12}{'TOTAL/mo':>11}{'vs IL':>9}"
    )
    print(header)
    print("-" * len(header))

    totals = {}
    for r in REGIONS:
        p = rows[r]
        pg = (p["pg_b1ms_hr"] or 0) * HOURS
        aca = ((p["aca_vcpu_s"] or 0) * 0.5 + (p["aca_mem_s"] or 0) * 1.0) * HOURS * 3600
        vm = (p["vm_b2s_hr"] or 0) * HOURS
        cold = (p["blob_cold_gb"] or p["blob_cool_gb"] or 0) * 300
        total = pg + aca + vm + cold
        totals[r] = total

    il = totals["israelcentral"]
    for r in sorted(REGIONS, key=lambda x: totals[x]):
        p = rows[r]
        pg = (p["pg_b1ms_hr"] or 0) * HOURS
        aca = ((p["aca_vcpu_s"] or 0) * 0.5 + (p["aca_mem_s"] or 0) * 1.0) * HOURS * 3600
        vm = (p["vm_b2s_hr"] or 0) * HOURS
        cold = (p["blob_cold_gb"] or p["blob_cool_gb"] or 0) * 300
        delta = totals[r] - il
        print(
            f"{r:<16}{fmt(pg):>10}{fmt(aca):>10}{fmt(vm):>10}"
            f"{fmt(cold):>12}{fmt(totals[r]):>11}{('%+.2f' % delta):>9}"
        )

    print()
    print("Block blob LRS, $/GB-month. 'archive n/a' means the region has no Archive tier:")
    print(f"{'region':<16}{'hot':>11}{'cool':>11}{'cold':>11}{'archive':>11}{'300GB@floor':>13}")
    for r in REGIONS:
        p = rows[r]
        floor = p["blob_archive_gb"] or p["blob_cold_gb"] or p["blob_cool_gb"]
        print(
            f"{r:<16}{fmt(p['blob_hot_gb'], digits=5):>11}"
            f"{fmt(p['blob_cool_gb'], digits=5):>11}{fmt(p['blob_cold_gb'], digits=5):>11}"
            f"{fmt(p['blob_archive_gb'], digits=5):>11}{fmt(floor, scale=300):>13}"
        )


if __name__ == "__main__":
    main()
