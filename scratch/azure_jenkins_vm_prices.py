#!/usr/bin/env python3
"""
Prices the Jenkins controller host in Israel Central, line by line, from the
public Azure Retail Prices API. No auth.

The VM itself is already covered by scratch/azure_region_compare.py; this fills
in the two lines that one skips — the managed disk holding JENKINS_HOME and the
static public IP — so the figure quoted in infra/AZURE_ACCESS_REQUEST.md is
checkable rather than asserted.

    python3 scratch/azure_jenkins_vm_prices.py
"""

import json
import urllib.parse
import urllib.request

REGION = "israelcentral"
BASE = "https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview"
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


def rows(flt, want=(), skip=("spot", "low priority")):
    seen = set()
    for i in fetch(flt):
        if i["type"] != "Consumption" or i["unitPrice"] == 0:
            continue
        name = i["meterName"]
        low = name.lower()
        if want and not any(w.lower() in low for w in want):
            continue
        if any(s in low for s in skip):
            continue
        seen.add((name, i["unitPrice"], i["unitOfMeasure"], i.get("skuName", "")))
    return sorted(seen, key=lambda x: x[1])


def show(title, items):
    print(f"\n{'=' * 78}\n{title}\n{'=' * 78}")
    if not items:
        print("  (nothing matched)")
        return
    for name, price, unit, sku in items:
        monthly = ""
        if "hour" in unit.lower():
            monthly = f"   -> ${price * HOURS:,.2f}/mo always on"
        elif "month" in unit.lower():
            monthly = f"   -> ${price:,.2f}/mo"
        print(f"  {name:<40} ${price:<12.6f} per {unit}{monthly}")


def main():
    show(
        "Standard_B2s Linux VM (2 vCPU / 4 GiB) - the Jenkins controller",
        rows(
            f"armRegionName eq '{REGION}' and serviceName eq 'Virtual Machines' "
            "and armSkuName eq 'Standard_B2s'",
            skip=("spot", "low priority", "windows"),
        ),
    )

    # E6 = 64 GiB Standard SSD, P6 = 64 GiB Premium SSD. Standard SSD is the
    # right call for JENKINS_HOME: job history and workspaces, not a database.
    show(
        "Managed disks - 64 GiB tiers for JENKINS_HOME",
        rows(
            f"armRegionName eq '{REGION}' and serviceName eq 'Storage' "
            "and productName eq 'Standard SSD Managed Disks'",
            want=["E6"],
        )
        + rows(
            f"armRegionName eq '{REGION}' and serviceName eq 'Storage' "
            "and productName eq 'Premium SSD Managed Disks'",
            want=["P6"],
        ),
    )

    show(
        "Public IP addresses",
        rows(
            f"armRegionName eq '{REGION}' and serviceName eq 'Virtual Network' "
            "and productName eq 'IP Addresses'",
            want=["static", "standard"],
        ),
    )


if __name__ == "__main__":
    main()
