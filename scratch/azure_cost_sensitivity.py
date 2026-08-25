#!/usr/bin/env python3
"""
Sensitivity of the Azure cost model to the storage assumption.

The first version of the report applied 1.5 GB per participant-day to every
participant every day and kept it forever. That figure is the midpoint of
"individual daily ZIPs can reach 1-2 GB" (backend/docs/MIGRATION_PLAN.md 2.3),
which is a stated ceiling, not a mean. azure_cost_report.py now models a mean
and an adherence rate instead; this script keeps the assumption as a free
variable so the range stays visible and can be rechecked once somebody
inventories the legacy Drive folder.

Row A below reproduces the old ceiling-as-mean assumption for comparison. It is
not as expensive as it once was, because the compute sizing it inherits from
azure_cost_report has also been corrected.

    python3 scratch/azure_cost_sensitivity.py
"""

from azure_cost_report import REGIONS, DPM, fixed, tiered, sizing, usd, size

IL = REGIONS["israelcentral"]


def split(r, n, months, gbpd, adherence, retain):
    """Bytes resident per tier, with retention capping unbounded growth."""
    per = n * gbpd * adherence * DPM          # GB added per month
    billed = per * min(months, retain)        # raw ZIPs still on the account
    hot = min(billed, per)                    # newest month stays hot
    cool = min(max(billed - hot, 0), per * 2)  # next two months cool
    return hot, cool, max(billed - hot - cool, 0), billed


def storage(r, n, months, gbpd, adherence, retain):
    hot, cool, floor, billed = split(r, n, months, gbpd, adherence, retain)
    warm = tiered(r["hot"], hot) + cool * r["cool"]
    return warm + floor * (r["arch"] or r["cold"]), billed


def total(r, n, months, gbpd, adherence, retain):
    f = fixed(r, n)["total"]
    st, billed = storage(r, n, months, gbpd, adherence, retain)
    return f, st, f + st, billed


FOREVER = 10_000

SCENARIOS = [
    ("A  old assumption: 1.5 GB/day, every day, kept forever", 1.5, 1.00, FOREVER),
    ("B  mean instead of peak ZIP size", 0.40, 1.00, FOREVER),
    ("C  B + realistic adherence (60% of days)", 0.40, 0.60, FOREVER),
    ("D  C + raw ZIPs retired after 12 months", 0.40, 0.60, 12),
]


def table(n, months):
    print(f"\n{n:,} participants, month {months}, Israel Central")
    print("-" * 92)
    print(f"{'scenario':<52}{'fixed':>10}{'storage':>10}{'total':>11}{'held':>10}")
    print("-" * 92)
    base = None
    for label, gbpd, adh, ret in SCENARIOS:
        f, st, tot, held = total(IL, n, months, gbpd, adh, ret)
        base = base or tot
        note = "" if tot == base else f"  {base/tot:.1f}x cheaper"
        print(f"{label:<52}{usd(f):>10}{usd(st):>10}{usd(tot):>11}{size(held):>10}{note}")


print("=" * 92)
print("How much of the bill is the storage guess?")
print("=" * 92)

print("\nStorage as a share of total, under the published assumption")
print("-" * 92)
print(f"{'participants':<14}{'fixed':>10}{'storage':>12}{'total':>12}{'storage share':>15}")
print("-" * 92)
for n in (43, 100, 250, 1000, 5000):
    f, st, tot, _ = total(IL, n, 12, 1.5, 1.0, FOREVER)
    print(f"{n:<14,}{usd(f):>10}{usd(st):>12}{usd(tot):>12}{st/tot*100:>14.0f}%")

for n, m in ((43, 12), (43, 36), (250, 12), (1000, 12)):
    table(n, m)

print("\n" + "=" * 92)
print("Break-even: what average ZIP size would justify the published figure?")
print("=" * 92)
for gbpd in (1.5, 1.0, 0.6, 0.4, 0.25, 0.1):
    f, st, tot, held = total(IL, 1000, 12, gbpd, 0.6, 12)
    print(f"  {gbpd:>4} GB/participant-day -> {usd(tot):>8}/mo at 1,000 participants "
          f"({size(held)} held)")
