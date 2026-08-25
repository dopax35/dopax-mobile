#!/usr/bin/env python3
"""
Pulls the billing UNIT for each thing we plan to run, straight from the public
Azure Retail Prices API, so the cost model can be checked multiplication by
multiplication instead of taken on faith.

No auth needed. Consumption prices only, Linux, Israel Central.

    python3 scratch/azure_unit_prices.py
"""

import json
import urllib.parse
import urllib.request

REGION = "israelcentral"
BASE = "https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview"


def fetch(flt):
    url = f"{BASE}&$filter={urllib.parse.quote(flt)}"
    items, pages = [], 0
    while url and pages < 6:
        with urllib.request.urlopen(url, timeout=60) as r:
            data = json.load(r)
        items += data.get("Items", [])
        url = data.get("NextPageLink")
        pages += 1
    return items


def show(title, flt, want=None, unit_hint=""):
    print(f"\n{'=' * 78}\n{title}\n{'=' * 78}")
    rows = []
    for i in fetch(flt):
        if i["type"] != "Consumption" or i["unitPrice"] == 0:
            continue
        name = i["meterName"]
        if want and not any(w.lower() in name.lower() for w in want):
            continue
        if "spot" in name.lower() or "low priority" in name.lower():
            continue
        rows.append((name, i["unitPrice"], i["unitOfMeasure"], i.get("skuName", "")))
    for name, price, unit, sku in sorted(set(rows), key=lambda x: x[1]):
        monthly = ""
        if "hour" in unit.lower():
            monthly = f"   -> ${price * 730:,.2f}/month if always on"
        print(f"  {name:<44} ${price:<12.8f} per {unit}{monthly}")
    if not rows:
        print("  (nothing matched)")


def main():
    show("PostgreSQL Flexible Server compute - billed PER HOUR the server exists",
         f"armRegionName eq '{REGION}' and serviceName eq 'Azure Database for PostgreSQL'",
         want=["B1ms", "B2s", "D2ds", "D4ds", "D8ds"])

    show("PostgreSQL storage - billed PER GB PROVISIONED PER MONTH (not per GB used)",
         f"armRegionName eq '{REGION}' and serviceName eq 'Azure Database for PostgreSQL'",
         want=["storage"])

    # Returns nothing in Israel Central: Container Apps is not offered in this
    # region. Kept so the empty result is visible rather than assumed.
    show("Container Apps - billed PER vCPU-SECOND and PER GiB-SECOND",
         f"armRegionName eq '{REGION}' and serviceName eq 'Azure Container Apps'")

    show("App Service Linux plan - billed PER HOUR the plan exists, not per app",
         f"armRegionName eq '{REGION}' and serviceName eq 'Azure App Service'",
         want=["B1", "B2", "B3", "P0 v3", "P1 v3", "P2 v3", "S1"])

    show("Container Instances - billed PER vCPU-SECOND and PER GB-SECOND (bootstrap)",
         f"armRegionName eq '{REGION}' and serviceName eq 'Container Instances'")

    show("Plain Linux VM - billed PER HOUR (the 'just give me a server' option)",
         f"armRegionName eq '{REGION}' and serviceName eq 'Virtual Machines'",
         want=["B2ms", "B2s", "B4ms", "D2s v5", "D4s v5", "D2as v5", "D4as v5"])

    show("Managed disk - billed PER DISK PER MONTH, flat, regardless of use",
         f"armRegionName eq '{REGION}' and serviceName eq 'Storage' "
         f"and contains(meterName, 'Disk')",
         want=["E10", "E15", "E20", "E30", "P10", "P15", "P20", "P30"])

    show("Blob storage - billed PER GB-MONTH STORED, per access tier",
         f"armRegionName eq '{REGION}' and serviceName eq 'Storage' "
         f"and contains(productName, 'Blob')",
         want=["Data Stored"])

    show("Log Analytics - billed PER GB OF LOGS INGESTED",
         f"armRegionName eq '{REGION}' and serviceName eq 'Azure Monitor'",
         want=["Data Ingestion", "Analytics Logs"])

    show("Bandwidth - billed PER GB LEAVING Azure (inbound is free)",
         f"armRegionName eq '{REGION}' and serviceName eq 'Bandwidth'",
         want=["Data Transfer Out", "Internet Egress"])


if __name__ == "__main__":
    main()
