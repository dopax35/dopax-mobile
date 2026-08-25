#!/usr/bin/env python3
"""
Renders the DopaX Azure cost model to a print-ready HTML report.

Same arithmetic as the azure-hosting-plan canvas, kept in one place so the PDF
and the interactive model cannot drift apart. Unit prices were read from the
Azure Retail Prices API on 2026-08-17; see PRICED_ON below.

    python3 scratch/azure_cost_report.py > scratch/azure-cost-model.html
"""

PRICED_ON = "17 August 2026"

# --- unit prices -----------------------------------------------------------
# Hot blob storage is volume-tiered as [(minimum GB, price per GB-month)].
# Cool, Cold, and Archive return a single flat tier from the pricing API.
#
#   b1 / b2   burstable Postgres, per hour       gp    General Purpose, per vCore-hour
#   ps        Postgres disk, per GB PROVISIONED  logs  Analytics ingestion, per GB
#   lb        Basic log ingestion, per GB        eg    egress, per GB past the free 100
#   va / vi   Container Apps vCPU-second, active / idle
#   ma / mi   Container Apps GiB-second, active / idle
#
# eg uses the first PAID egress band, which is the most expensive one; Azure
# gives 100 GB/month free and the rate falls as volume rises, so this is a
# deliberate upper bound at study scale.
REGIONS = {
    "israelcentral": dict(
        label="Israel Central", short="Israel", in_country=True,
        va=3.4e-5, vi=4e-6, ma=4e-6, mi=4e-6,
        b1=0.022, b2=0.088, gp=0.1085, ps=0.164,
        hot=[(0, 0.02), (51_200, 0.0192), (512_000, 0.0184)],
        cool=0.01104, cold=0.0045, arch=None, acr=0.1666,
        logs=3.29, lb=0.66, eg=0.087),
    "swedencentral": dict(
        label="Sweden Central", short="Sweden", in_country=False,
        va=2.4e-5, vi=3e-6, ma=3e-6, mi=3e-6,
        b1=0.0199, b2=0.0398, gp=0.0935, ps=0.1369,
        hot=[(0, 0.0184), (51_200, 0.017649), (512_000, 0.016899)],
        cool=0.01, cold=0.0036, arch=0.00099, acr=0.1666,
        logs=2.99, lb=0.645, eg=0.087),
    "northeurope": dict(
        label="North Europe", short="N. Europe", in_country=False,
        va=2.4e-5, vi=3e-6, ma=3e-6, mi=3e-6,
        b1=0.018, b2=0.072, gp=0.0988, ps=0.1265,
        hot=[(0, 0.022), (51_200, 0.0211), (512_000, 0.0202)],
        cool=0.01, cold=0.0036, arch=0.00099, acr=0.1666,
        logs=2.76, lb=0.60, eg=0.087),
    "westeurope": dict(
        label="West Europe", short="W. Europe", in_country=False,
        va=3.4e-5, vi=4e-6, ma=4e-6, mi=4e-6,
        b1=0.0199, b2=0.0796, gp=0.106, ps=0.1369,
        hot=[(0, 0.0196), (51_200, 0.0188), (512_000, 0.018)],
        cool=0.01, cold=0.0045, arch=0.0018, acr=0.1666,
        logs=2.99, lb=0.65, eg=0.087),
    "germanywestcentral": dict(
        label="Germany West Central", short="Germany", in_country=False,
        va=2.4e-5, vi=3e-6, ma=3e-6, mi=3e-6,
        b1=0.0199, b2=0.0796, gp=0.106, ps=0.137,
        hot=[(0, 0.0196), (51_200, 0.0188), (512_000, 0.018)],
        cool=0.01, cold=0.0045, arch=0.0018, acr=0.1666,
        logs=2.99, lb=0.65, eg=0.087),
    "francecentral": dict(
        label="France Central", short="France", in_country=False,
        va=2.4e-5, vi=3e-6, ma=3e-6, mi=3e-6,
        b1=0.019, b2=0.076, gp=0.103, ps=0.133,
        hot=[(0, 0.019), (51_200, 0.0184), (512_000, 0.017664)],
        cool=0.0105, cold=0.0045, arch=0.00211, acr=0.1666,
        logs=2.76, lb=0.625, eg=0.087),
    "uksouth": dict(
        label="UK South", short="UK", in_country=False,
        va=3.4e-5, vi=4e-6, ma=4e-6, mi=4e-6,
        b1=0.019, b2=0.076, gp=0.103, ps=0.133,
        hot=[(0, 0.019), (51_200, 0.0184), (512_000, 0.017664)],
        cool=0.011, cold=0.0045, arch=0.0018, acr=0.1666,
        logs=2.88, lb=0.625, eg=0.087),
    "eastus": dict(
        label="East US", short="East US", in_country=False,
        va=2.4e-5, vi=3e-6, ma=3e-6, mi=3e-6,
        b1=0.017, b2=0.068, gp=0.089, ps=0.115,
        hot=[(0, 0.0208), (51_200, 0.019968), (512_000, 0.0191)],
        cool=0.0152, cold=0.0036, arch=0.00099, acr=0.1666,
        logs=2.3, lb=0.50, eg=0.087),
}

SPM = 730 * 3600          # billable seconds in a month
DPM = 30.4                # days per month

# --- the storage assumption, which decides most of the bill -----------------
# MIGRATION_PLAN 2.3 says "individual daily ZIPs can reach 1-2 GB". That is a
# CEILING observed on the heaviest days, not an average, and the legacy Drive
# folder has never been inventoried, so the true mean is unmeasured.
#
# Applying the ceiling to every participant on every day is what produced the
# alarming figures in the first version of this report. We now model a mean and
# an adherence rate separately, and print both bounds.
#
# PEAK_GBPD stays here only to show the upper bound for comparison.
PEAK_GBPD = 1.5           # the old assumption: ceiling used as a mean
MEAN_GBPD = 0.40          # planning mean per uploading participant-day
ADHERENCE = 0.60          # share of participant-days that actually upload
RETAIN_MONTHS = None      # None = keep raw ZIPs forever, per current policy

# Logs are dominated by health probes, not by participants: liveness every 30 s
# plus readiness every 10 s is ~12k probe lines a day before any upload arrives.
LOG_BASE_GB = 0.5         # per month, platform and probe noise
LOG_GB_PER_UPLOAD = 5e-6  # ~5 KB of request and job output per upload

SIZES = [43, 100, 250, 500, 1000, 2500, 5000, 10_000, 20_000]


def log_gb(n):
    """Monthly log ingestion. Was a hand-picked table an order of magnitude high."""
    return LOG_BASE_GB + n * DPM * ADHERENCE * LOG_GB_PER_UPLOAD


def sizing(n):
    """
    Derive infrastructure from enrolment so each row stays self-consistent.

    `pg` names the Postgres tier: raw ZIPs live in blob storage, so this server
    only holds metadata (~30 rows per participant-day). B1ms carries study scale
    comfortably, which is why the small tiers no longer jump straight to B2s.

    `rep` is minReplicas for the API. It is 1 rather than 0 on purpose: a cold
    start in front of a phone uploading on cellular risks the upload, and that
    is worth more than the ~$14/month it saves. See apiAlwaysWarm in main.bicep.
    """
    if n <= 150:
        return dict(t="Burstable B1ms", pg="b1", vc=1, st=32, rep=1,
                    av=.5, am=1, aa=.10, dv=.5, dm=1, da=.05)
    if n <= 400:
        return dict(t="Burstable B2s", pg="b2", vc=2, st=64, rep=1,
                    av=.5, am=1, aa=.15, dv=.5, dm=1, da=.06)
    if n <= 800:
        return dict(t="GP D2ds_v5", pg="gp", vc=2, st=128, rep=2,
                    av=1, am=2, aa=.20, dv=.5, dm=1, da=.08)
    if n <= 1500:
        return dict(t="GP D2ds_v5", pg="gp", vc=2, st=256, rep=2,
                    av=1, am=2, aa=.25, dv=1, dm=2, da=.10)
    if n <= 4000:
        return dict(t="GP D4ds_v5", pg="gp", vc=4, st=512, rep=3,
                    av=1, am=2, aa=.30, dv=1, dm=2, da=.12)
    if n <= 12_000:
        return dict(t="GP D8ds_v5", pg="gp", vc=8, st=1024, rep=6,
                    av=2, am=4, aa=.35, dv=1, dm=2, da=.15)
    return dict(t="GP D16ds_v5", pg="gp", vc=16, st=2048, rep=10,
                av=2, am=4, aa=.40, dv=1, dm=2, da=.20)


def tiered(tiers, gb):
    cost = 0.0
    for i, (lo, price) in enumerate(tiers):
        if gb <= lo:
            break
        hi = tiers[i + 1][0] if i + 1 < len(tiers) else float("inf")
        cost += (min(gb, hi) - lo) * price
    return cost


def replica(r, vcpu, mem, active):
    """minReplicas>=1. The memory reservation is billed all month, idle or not."""
    a = SPM * active
    idle = SPM - a
    return vcpu * (a * r["va"] + idle * r["vi"]) + mem * (a * r["ma"] + idle * r["mi"])


def scale_to_zero(r, vcpu, mem, active):
    """minReplicas=0. Nothing is allocated between bursts, so nothing is billed."""
    a = SPM * active
    return vcpu * a * r["va"] + mem * a * r["ma"]


def job(r, runs, seconds, vcpu, mem):
    s = runs * seconds
    return vcpu * s * r["va"] + mem * s * r["ma"]


def uploads_per_month(n):
    """Only participant-days that actually produce a ZIP cost anything."""
    return n * DPM * ADHERENCE


def pg_hourly(r, s):
    return {"b1": r["b1"], "b2": r["b2"]}.get(s["pg"], r["gp"] * s["vc"])


def fixed(r, n, ha=False):
    s = sizing(n)
    api = replica(r, s["av"], s["am"], s["aa"]) * s["rep"]
    # The staff console runs minReplicas=0 in main.bicep, so it is billed only
    # while someone is using it rather than for holding a GiB open all month.
    admin = scale_to_zero(r, s["dv"], s["dm"], s["da"])
    ingest = job(r, uploads_per_month(n), 240, 2, 4)
    recon = job(r, DPM, 600, 1, 2)
    compute = api + admin + ingest + recon
    grant = min(180_000 * r["va"] + 360_000 * r["ma"], compute)
    pg = (pg_hourly(r, s) * 730 + s["st"] * r["ps"]) * (2 if ha else 1)
    registry = r["acr"] * DPM
    # Basic table plan, not Analytics: app console logs are read when something
    # breaks, not queried analytically. See useBasicLogTier in main.bicep.
    logs = log_gb(n) * r["lb"]
    return dict(api=api, admin=admin, ingest=ingest, recon=recon, grant=grant,
                pg=pg, registry=registry, logs=logs, kv=1,
                total=compute - grant + pg + registry + logs + 1)


def monthly_growth(n, gbpd=None):
    """GB added to the archive per month."""
    return n * (gbpd if gbpd is not None else MEAN_GBPD) * ADHERENCE * DPM


def split(n, months, gbpd=None, retain=None):
    per = monthly_growth(n, gbpd)
    retain = retain if retain is not None else (RETAIN_MONTHS or months)
    billed = per * min(months, retain)
    hot = min(billed, per)
    cool = min(max(billed - hot, 0), per * 2)
    return hot, cool, max(billed - hot - cool, 0), billed


def storage(r, n, months, gbpd=None, retain=None):
    hot, cool, floor, total = split(n, months, gbpd, retain)
    warm = tiered(r["hot"], hot) + cool * r["cool"]
    return warm + floor * (r["arch"] if r["arch"] else r["cold"]), total


# Researchers pulling data back out is billable and was missing from the first
# version of this report. Ingress is always free, so device uploads cost nothing.
EGRESS_SHARE = 0.05       # share of each month's new data pulled out for analysis
EGRESS_FREE_GB = 100      # Azure's monthly allowance


def egress(r, n):
    gb = monthly_growth(n) * EGRESS_SHARE
    return max(gb - EGRESS_FREE_GB, 0) * r["eg"], gb


def all_in(r, n, months, ha=False):
    return (fixed(r, n, ha)["total"]
            + storage(r, n, months)[0]
            + egress(r, n)[0])


def usd(v):
    if v >= 1_000_000:
        return f"${v/1_000_000:,.2f}M"
    return f"${v:,.0f}"


def size(gb):
    if gb >= 1_048_576:
        return f"{gb/1_048_576:.2f} PB"
    if gb >= 1024:
        return f"{gb/1024:,.1f} TB"
    return f"{gb:,.0f} GB"


# --- report ----------------------------------------------------------------
IL = REGIONS["israelcentral"]
SE = REGIONS["swedencentral"]
H = 12  # horizon, months


def scale_rows():
    out = []
    for n in SIZES:
        f = fixed(IL, n)
        st, held = storage(IL, n, H)
        eg, _ = egress(IL, n)
        total = f["total"] + st + eg
        # Same arithmetic under the discarded ceiling-as-mean assumption, to show
        # how much of the old alarm was the assumption rather than the workload.
        peak = f["total"] + storage(IL, n, H, gbpd=PEAK_GBPD)[0] + eg
        cls = "danger" if n >= 10_000 else ("warn" if n >= 2500 else "")
        out.append(
            f'<tr class="{cls}"><td class="n">{n:,}</td><td>{sizing(n)["t"]}</td>'
            f'<td class="n">{size(monthly_growth(n))}</td><td class="n">{size(held)}</td>'
            f'<td class="n">{usd(f["total"])}</td><td class="n">{usd(st + eg)}</td>'
            f'<td class="n b">{usd(total)}</td>'
            f'<td class="n">{usd(peak)}</td></tr>'
        )
    return "\n".join(out)


def region_rows(n):
    ranked = sorted(REGIONS.values(), key=lambda r: all_in(r, n, H))
    cheapest = all_in(ranked[0], n, H)
    out = []
    for r in ranked:
        f = fixed(r, n)
        st, _ = storage(r, n, H)
        eg, _ = egress(r, n)
        total = f["total"] + st + eg
        delta = total - cheapest
        floor = (f'Archive ${r["arch"]}' if r["arch"]
                 else f'Cold ${r["cold"]} &mdash; no Archive')
        cls = "warn" if r["in_country"] else ("ok" if delta == 0 else "")
        out.append(
            f'<tr class="{cls}"><td>{r["label"]}</td>'
            f'<td>{"In Israel" if r["in_country"] else "Outside Israel"}</td>'
            f'<td>{floor}</td><td class="n">{usd(f["total"])}</td>'
            f'<td class="n">{usd(st)}</td><td class="n b">{usd(total)}</td>'
            f'<td class="n">{"&mdash;" if delta == 0 else "+" + usd(delta)}</td></tr>'
        )
    return "\n".join(out)


def bom_rows(n):
    r, s, f = IL, sizing(n), fixed(IL, n)
    st, held = storage(IL, n, H)
    eg, eg_gb = egress(IL, n)
    rows = [
        ("Backend API", f'Container Apps · {s["av"]} vCPU / {s["am"]} GiB, {s["rep"]} always warm',
         f'${r["va"]}/vCPU-s active, ${r["vi"]} idle; memory billed all month',
         usd(f["api"])),
        ("Admin console", f'Container Apps · {s["dv"]} vCPU / {s["dm"]} GiB, scales to zero',
         "Billed only while staff are using it", usd(f["admin"])),
        ("Ingestion jobs", f'Container Apps Jobs · {round(uploads_per_month(n)):,} runs/mo, 4 min at 2 vCPU',
         f'{ADHERENCE:.0%} of participant-days upload', usd(f["ingest"])),
        ("Reconciler job", "Container Apps Jobs · nightly cron, 10 min at 1 vCPU",
         "Guardrail R3 counts 14 clean runs", usd(f["recon"])),
        ("Free grant", "180k vCPU-s + 360k GiB-s per subscription",
         "Applied once across all apps and jobs", "&minus;" + usd(f["grant"])),
        ("Database", f'PostgreSQL Flexible Server · {s["t"]}',
         f'${pg_hourly(r, s):.4f}/hr + ${r["ps"]}/GB-mo × {s["st"]:,} GB provisioned',
         usd(f["pg"])),
        ("Raw ZIP archive", f'Blob Storage GPv2 LRS · {size(held)} at month {H}',
         f'Hot ${r["hot"][-1][1]}&ndash;{r["hot"][0][1]} tiered · Cool ${r["cool"]} · Cold ${r["cold"]}',
         usd(st)),
        ("Image registry", "Container Registry · Basic", f'${r["acr"]}/day', usd(f["registry"])),
        ("Secrets", "Key Vault Standard", "$0.0396 per 10k operations", usd(f["kv"])),
        ("Logs", f'Log Analytics Basic plan · {log_gb(n):.1f} GB/mo, capped at 0.5 GB/day',
         f'${r["lb"]}/GB Basic instead of ${r["logs"]}/GB Analytics', usd(f["logs"])),
        ("Researcher downloads", f'Egress · {eg_gb:,.0f} GB/mo at {EGRESS_SHARE:.0%} of new data',
         f'First {EGRESS_FREE_GB} GB free, then ${r["eg"]}/GB', usd(eg)),
        ("Participant uploads", "Inbound data transfer",
         "Ingress is always free, at any volume", "$0"),
    ]
    return "\n".join(
        f"<tr><td>{a}</td><td>{b}</td><td class='sm'>{c}</td><td class='n'>{d}</td></tr>"
        for a, b, c, d in rows
    )


def premium_rows():
    out = []
    for n in [43, 250, 1000, 5000, 20_000]:
        a, b = all_in(IL, n, H), all_in(SE, n, H)
        out.append(
            f'<tr><td class="n">{n:,}</td><td class="n">{usd(a)}</td>'
            f'<td class="n">{usd(b)}</td><td class="n b">+{usd(a-b)}</td>'
            f'<td class="n">+{(a-b)/b*100:.0f}%</td></tr>'
        )
    return "\n".join(out)


now = fixed(IL, 43)
now_st, now_held = storage(IL, 43, H)
now_eg = egress(IL, 43)[0]
k1 = fixed(IL, 1000)
k1_st, _ = storage(IL, 1000, H)
k1_eg = egress(IL, 1000)[0]

HTML = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>DopaX on Azure — hosting cost model</title>
<style>
  @page {{ size: A4; margin: 15mm 14mm 16mm 14mm; }}
  * {{ box-sizing: border-box; }}
  body {{ font: 10pt/1.5 -apple-system, "Helvetica Neue", Arial, sans-serif;
         color: #14161a; margin: 0; -webkit-print-color-adjust: exact; }}
  h1 {{ font-size: 20pt; margin: 0 0 4px; letter-spacing: -.4px; }}
  h2 {{ font-size: 12.5pt; margin: 26px 0 8px; padding-bottom: 5px;
        border-bottom: 1.5px solid #14161a; page-break-after: avoid; }}
  h3 {{ font-size: 10.5pt; margin: 18px 0 6px; page-break-after: avoid; }}
  p  {{ margin: 0 0 9px; }}
  .lede {{ color: #55595f; font-size: 9.5pt; margin: 0 0 2px; }}
  .rule {{ height: 3px; background: #14161a; margin: 12px 0 18px; }}
  /* Tables flow across a page break rather than being pushed whole, which used
     to strand a heading above half a blank page. Rows stay intact. */
  table {{ width: 100%; border-collapse: collapse; margin: 8px 0 6px;
           font-size: 8.7pt; }}
  tr {{ page-break-inside: avoid; }}
  thead {{ display: table-header-group; }}
  th {{ text-align: left; font-weight: 600; border-bottom: 1.2px solid #14161a;
        padding: 5px 6px; }}
  td {{ padding: 4.5px 6px; border-bottom: .5px solid #dcdee1; vertical-align: top; }}
  td.n, th.n {{ text-align: right; white-space: nowrap; }}
  td.b {{ font-weight: 700; }}
  td.sm {{ font-size: 7.9pt; color: #55595f; }}
  tr.warn td {{ background: #fdf6e6; }}
  tr.danger td {{ background: #fbecec; }}
  tr.ok td {{ background: #eef7ee; }}
  .cards {{ display: flex; gap: 10px; margin: 14px 0 4px; }}
  .card {{ flex: 1; border: 1px solid #c9ccd1; padding: 9px 11px; }}
  .card .v {{ font-size: 15pt; font-weight: 700; letter-spacing: -.3px; }}
  .card .l {{ font-size: 7.8pt; color: #55595f; text-transform: uppercase;
              letter-spacing: .4px; margin-top: 2px; }}
  .note {{ border-left: 3px solid #14161a; padding: 8px 12px; margin: 12px 0;
           background: #f5f6f7; font-size: 9pt; }}
  .note.warn {{ border-color: #b58900; background: #fdf6e6; }}
  .note.stop {{ border-color: #b3312c; background: #fbecec; }}
  .note b {{ display: block; margin-bottom: 3px; }}
  .cap {{ font-size: 7.9pt; color: #6b6f75; margin: 2px 0 0; }}
  ol {{ margin: 6px 0 0 16px; padding: 0; font-size: 9pt; }}
  ol li {{ margin-bottom: 6px; }}
  footer {{ margin-top: 22px; padding-top: 8px; border-top: .5px solid #dcdee1;
            font-size: 7.6pt; color: #6b6f75; }}
  .pb {{ page-break-before: always; }}
  code {{ font: 8.4pt ui-monospace, Menlo, monospace; background: #f0f1f2;
          padding: 1px 3px; }}
</style></head><body>

<p class="lede">DopaX &mdash; Parkinson's data collection study &middot; infrastructure costing</p>
<h1>Hosting DopaX on Azure</h1>
<p class="lede">Region selection and cost at scale &middot; list prices read from the
Azure Retail Prices API on {PRICED_ON}</p>
<div class="rule"></div>

<h2>Summary</h2>
<p>The deployment targets <b>Azure Container Apps</b> for the API, staff console and
background workers, <b>PostgreSQL Flexible Server</b> as the system of record, and
<b>Blob Storage</b> for the raw sensor archive, all in <b>Israel Central</b> so that
participant health data stays in the country. The infrastructure is written and
validated in <code>infra/main.bicep</code>; deployment is blocked only on Azure
access.</p>

<div class="cards">
  <div class="card"><div class="v">{usd(now['total'] + now_st + now_eg)}</div>
    <div class="l">Per month, 43 participants, year 1</div></div>
  <div class="card"><div class="v">{usd(k1['total'] + k1_st + k1_eg)}</div>
    <div class="l">Per month at 1,000 participants</div></div>
  <div class="card"><div class="v">{size(now_held)}</div>
    <div class="l">Archive held after 12 months</div></div>
  <div class="card"><div class="v">{(now_st/(now['total']+now_st))*100:.0f}&ndash;52%</div>
    <div class="l">Share of the bill that is storage</div></div>
</div>
<p class="cap">All figures are month-12 monthly run rates. Storage accumulates
indefinitely, so the monthly total rises every month the study runs.</p>

<div class="note warn">
  <b>Read the storage assumption before using any number here</b>
  The archive is the only line that grows without bound, so the assumed data volume
  decides most of this report &mdash; and it is unmeasured. The migration plan records
  that daily ZIPs <i>can reach</i> 1&ndash;2&nbsp;GB, a ceiling on the heaviest days, and
  the legacy Drive folder has never been inventoried. These figures assume a mean of
  {MEAN_GBPD}&nbsp;GB per uploading participant-day at {ADHERENCE:.0%} adherence; the last
  column of the next table applies the ceiling as an average instead, which is about
  {(fixed(IL, 1000)['total'] + storage(IL, 1000, H, gbpd=PEAK_GBPD)[0]) / (fixed(IL, 1000)['total'] + storage(IL, 1000, H)[0]):.1f}&times;
  higher. Reading the real folder size is the highest-value action available and needs no
  Azure access. Today the bill splits fairly evenly &mdash; archive {usd(now_st)},
  database {usd(now['pg'])}, warm API replica {usd(now['api'])}, ingestion
  {usd(now['ingest'])} &mdash; so storage only dominates with scale and time.
</div>

<h2>Cost by study size &mdash; Israel Central</h2>
<p>Database tier and API replica count are derived from enrolment rather than chosen by
hand, so each row is internally consistent. Every row assumes 12 months of elapsed
study, the lifecycle rule in the template, and that nothing is ever deleted.</p>
<table>
  <thead><tr>
    <th class="n">Participants</th><th>Database tier</th><th class="n">New data / mo</th>
    <th class="n">Held at 12 mo</th><th class="n">Platform / mo</th>
    <th class="n">Storage + egress</th><th class="n">All-in / mo</th>
    <th class="n">If 1.5 GB/day</th>
  </tr></thead>
  <tbody>
{scale_rows()}
  </tbody>
</table>
<p class="cap">Growth uses {MEAN_GBPD}&nbsp;GB per uploading participant-day at
{ADHERENCE:.0%} adherence, so one participant produces about
{monthly_growth(1):.0f}&nbsp;GB a month. The last column is the same arithmetic with the
1&ndash;2&nbsp;GB ceiling from <code>backend/docs/MIGRATION_PLAN.md</code> &sect;2.3 used
as a daily average, which is what the first version of this report did. Rows at 10,000
and above are arithmetic for completeness, not a plan; see the ceiling below.</p>

<div class="note stop">
  <b>Above roughly 2,500 participants this architecture is the wrong answer</b>
  Three things break well before the 20,000 row. Ingest reaches
  {size(monthly_growth(20_000))} a month, roughly
  {monthly_growth(20_000)/DPM/1024:.1f}&nbsp;TB a day arriving &mdash; a sustained feed
  rather than background uploads from phones. Ingestion becomes
  {uploads_per_month(20_000):,.0f} job executions a month, past what Container Apps Jobs
  is designed to schedule; the design would move to a queue with a long-lived consumer
  pool. And nobody buys storage at this volume at list price: Azure reserved capacity at
  100&nbsp;TB or 1&nbsp;PB commitments discounts 25&ndash;38%, which these figures
  deliberately exclude. Most importantly, retaining every raw sensor ZIP forever is
  affordable at 43 participants and indefensible at 20,000, where it means
  {size(storage(IL, 20_000, H)[1])} after one year. Long before that scale the study
  would keep derived features and discard raw signal after a window &mdash; a
  research-design decision, not an infrastructure one.
</div>

<div class="pb"></div>

<h2>Which region is cheapest</h2>
<p>All-in monthly spend in month 12 at 1,000 participants, each region using the coldest
storage tier it actually offers. Israel Central is the only option that satisfies
in-country residency, and it is also the most expensive on almost every meter.</p>
<table>
  <thead><tr>
    <th>Region</th><th>Residency</th><th>Coldest tier</th><th class="n">Platform / mo</th>
    <th class="n">Storage / mo</th><th class="n">All-in / mo</th><th class="n">vs cheapest</th>
  </tr></thead>
  <tbody>
{region_rows(1000)}
  </tbody>
</table>
<p class="cap">Shaded green: cheapest. Shaded amber: the in-country option, which is the
one the template uses.</p>

<h3>What residency costs, by study size</h3>
<table>
  <thead><tr><th class="n">Participants</th><th class="n">Israel Central</th>
    <th class="n">Sweden Central</th><th class="n">Premium</th><th class="n">%</th>
  </tr></thead>
  <tbody>
{premium_rows()}
  </tbody>
</table>
<p class="cap">The premium runs
{min((all_in(IL, n, H) - all_in(SE, n, H)) / all_in(SE, n, H) for n in [43, 250, 1000, 5000, 20_000]) * 100:.0f}&ndash;{max((all_in(IL, n, H) - all_in(SE, n, H)) / all_in(SE, n, H) for n in [43, 250, 1000, 5000, 20_000]) * 100:.0f}%
across the range, so it will not improve with scale.</p>

<h3>Why Israel Central costs more</h3>
<p>Three structural differences. Container Apps compute is priced 42% above the cheap
European tier &mdash; ${IL['va']} per vCPU-second against ${SE['va']} &mdash; and because
ingestion runs one job per uploaded participant-day, that premium tracks enrolment
directly. The database is {(IL['b1']/SE['b1'] - 1) * 100:.0f}% more per hour for the same
burstable SKU. Most significantly, <b>Israel Central offers no Archive blob tier at
all</b>, so Cold LRS at ${IL['cold']}/GB-month is the floor, against ${SE['arch']} in
Sweden or North Europe &mdash; {IL['cold']/SE['arch']:.1f}&times; on the tier that
eventually holds nearly all of the data. Logging is no longer a factor now that console
logs sit on the Basic plan: ${IL['lb']}/GB against ${SE['lb']}.</p>

<div class="note warn">
  <b>The one lever that would change the storage bill</b>
  If the ethics approval permits de-identified raw ZIPs to sit in the EU while
  identifiable records stay in PostgreSQL in Israel, a split deployment becomes worth
  costing: database and API in Israel Central, cold archive in Sweden Central or North
  Europe on Archive LRS at ${SE['arch']} &mdash; about a
  {(1 - storage(SE, 1000, H)[0] / storage(IL, 1000, H)[0]) * 100:.0f}% cut to the storage
  line at 1,000 participants. This
  is a question for the ethics board, not a technical decision. The template
  deliberately keeps everything in Israel Central, which is the conservative and
  defensible default. Moving participant data across a border on cost grounds alone is
  exactly the kind of change that fails an audit.
</div>

<div class="pb"></div>

<h2>What gets provisioned today &mdash; 43 participants, Israel Central</h2>
<table>
  <thead><tr><th>Component</th><th>Service and SKU</th><th>Unit price</th>
    <th class="n">Est. / month</th></tr></thead>
  <tbody>
{bom_rows(43)}
  </tbody>
</table>
<p class="cap">Every line is a real Azure meter at pay-as-you-go list price. Storage is
shown at its month-12 volume.</p>

<h2>What this model assumes</h2>
<ol>
  <li><b>The data volume is unmeasured, and it decides the report.</b>
  <code>MIGRATION_PLAN.md</code> &sect;2.3 records that daily ZIPs <i>can reach</i>
  1&ndash;2&nbsp;GB. That is a ceiling on the heaviest days, not an average, and the
  legacy Drive folder has never been inventoried. These figures assume a mean of
  {MEAN_GBPD}&nbsp;GB per uploading participant-day and {ADHERENCE:.0%} adherence, both
  estimates. Reading the real folder size and file count replaces the largest source of
  error in this document and requires no Azure access at all.</li>
  <li><b>Nothing is ever deleted.</b> Matching the lifecycle policy in the template,
  which tiers but never expires. The retention policy for raw ZIPs is still an open
  question in the migration plan (&sect;13). Retiring raw archives after twelve months
  turns the storage line from a permanently rising cost into a flat one, and is the
  second-largest lever after the volume assumption.</li>
  <li><b>Hot storage is volume-tiered; Cool and Cold are not.</b> Hot bills
  $0.02/GB-month up to 50 TB, $0.0192 to 500 TB, then $0.0184 in Israel Central, applied
  progressively. Cool, Cold and Archive return a single flat tier from the pricing
  API.</li>
  <li><b>Ingestion is the biggest guess in the compute model.</b> One execution per
  uploaded participant-day, four minutes at 2 vCPU and 4 GiB. At 43 participants that is
  {usd(fixed(IL, 43)['ingest'])} a month; at 2,500 it is a top-three line and worth
  measuring against a real ZIP before anyone budgets on it.</li>
  <li><b>Egress is an estimate, and it was missing entirely from the first version of
  this report.</b> It assumes researchers pull back {EGRESS_SHARE:.0%} of each month's new
  data for analysis, against a {EGRESS_FREE_GB}&nbsp;GB monthly free allowance, at the
  most expensive band. Uploads into Azure are free at any volume, so data collection
  itself costs nothing to receive.</li>
  <li><b>Compute is sized for the load, not for reassurance.</b> The database is
  Burstable B1ms up to 150 participants because raw ZIPs live in blob storage and the
  server holds only metadata &mdash; roughly 30 rows per participant-day. One API replica
  is kept warm deliberately: Container Apps bills allocated capacity per second, so a
  warm replica costs about {usd(fixed(IL, 43)['api'])} a month whether traffic arrives or
  not, and scaling it to zero would save roughly $14 at the risk of a cold start in front
  of a phone uploading on cellular. The staff console does scale to zero.</li>
  <li><b>Sweden's Burstable rate looks anomalous.</b> B2s prices at $0.0398/hr against
  $0.088 in Israel &mdash; less than half, while its General Purpose rate is only 14%
  cheaper. Worth verifying in the portal before relying on the regional comparison at
  small enrolments.</li>
  <li><b>Quota is not the same as availability.</b> Every service and SKU here was
  confirmed present in Israel Central via the pricing API, but a new subscription
  commonly starts with zero cores in the region. Container Apps vCPU and Burstable
  vCores both need confirming before the first deploy.</li>
  <li><b>List prices only.</b> No EA or CSP discount, no reserved instances, no savings
  plan. A one-year reservation cuts General Purpose PostgreSQL compute by roughly 40%,
  and storage reserved capacity discounts 25&ndash;38%. Both matter from the
  250-participant row upward and neither is included.</li>
  <li><b>The HIPAA BAA covers Azure, not Firebase.</b> Container Apps, PostgreSQL, Blob
  Storage, Key Vault and Container Registry are all in scope at no extra cost. Firebase
  Auth remains the identity provider under guardrail R1, so participant emails stay with
  Google and outside that BAA &mdash; a decision to record deliberately rather than
  discover during an audit.</li>
</ol>

<h2>Deployment status</h2>
<table>
  <thead><tr><th>Piece</th><th>State</th></tr></thead>
  <tbody>
    <tr class="ok"><td><code>backend/Dockerfile</code></td><td>Written. Multi-stage Node 22; runtime, release and worker targets; migrations copied in.</td></tr>
    <tr class="ok"><td><code>admin/Dockerfile</code></td><td>Written. Next.js standalone output, builds and runs.</td></tr>
    <tr class="ok"><td><code>infra/main.bicep</code></td><td>Written, compiles clean. Two-pass deploy via <code>deployApplications</code>. Right-sized: B1ms database on a 32&nbsp;GB floor, console logs on the Basic plan, staff console scaling to zero.</td></tr>
    <tr class="ok"><td><code>infra/deploy.sh</code></td><td>Written. Idempotent; supports <code>--what-if</code> and <code>--infra-only</code>.</td></tr>
    <tr class="ok"><td><code>.github/workflows/deploy.yml</code></td><td>Written. Lint, typecheck, test, build, push, deploy on federated credentials.</td></tr>
    <tr class="danger"><td>Azure subscription</td><td><b>Missing.</b> The tenant has no subscription, so nothing can be deployed yet. This is the only blocker.</td></tr>
    <tr class="warn"><td><code>backend/src/storage/</code></td><td>Absent. <code>env.ts</code> validates <code>STORAGE_BACKEND=azure</code> but nothing implements it.</td></tr>
    <tr class="warn"><td>Reconciler entrypoint</td><td>Placeholder. The job is scheduled so the cron is reviewable; the command is a stub.</td></tr>
  </tbody>
</table>

<h3>What is needed from the Azure administrator</h3>
<ol>
  <li>A <b>subscription</b>, and its subscription ID. If an Enterprise Agreement or
  Microsoft Customer Agreement already exists, this needs no new payment method.</li>
  <li><b>Owner on a dedicated resource group</b>, not Contributor. The template creates
  three role assignments to bind the workload identity to the registry, storage account
  and vault; that requires
  <code>Microsoft.Authorization/roleAssignments/write</code>, which Contributor
  excludes. With Contributor the deployment fails midway, after the database exists.</li>
  <li><b>Resource providers registered</b> at subscription scope:
  <code>Microsoft.App</code>, <code>ContainerRegistry</code>,
  <code>DBforPostgreSQL</code>, <code>Storage</code>, <code>KeyVault</code>,
  <code>ManagedIdentity</code>, <code>OperationalInsights</code>,
  <code>Insights</code>, <code>Network</code>.</li>
  <li><b>Israel Central permitted and quota confirmed</b> &mdash; at least 10 vCPU for
  Container Apps and 2 Burstable vCores for PostgreSQL. Quota requests take a day or
  two.</li>
  <li><b>Confirmation that no policy forbids public endpoints</b> on managed services. If
  private endpoints are mandated, that is a design change (VNet integration) and needs
  deciding before the build, not after.</li>
  <li><b>Confirmation that the HIPAA BAA covers the subscription.</b></li>
  <li><b>Budget approval and a budget alert</b> on the resource group.</li>
</ol>
<p class="cap">The full request, with the exact commands, is in
<code>infra/AZURE_ACCESS_REQUEST.md</code> (Hebrew version:
<code>AZURE_ACCESS_REQUEST.he.md</code>).</p>

<footer>
All unit prices are pay-as-you-go list rates read directly from the Azure Retail Prices
API on {PRICED_ON}, filtered to the exact meters consumed by the resources declared in
<code>infra/main.bicep</code>, across the eight regions compared. They exclude EA and
CSP discounts, reserved instances and savings plans. Compute sizing is an estimate for a
low-traffic internal study, not a quote. Storage growth assumes {MEAN_GBPD}&nbsp;GB per
uploading participant-day at {ADHERENCE:.0%} adherence &mdash; an estimate, not a
measurement &mdash; and that nothing is ever deleted, matching the lifecycle policy in the
template. Re-check any unit price with
<code>scratch/azure_unit_prices.py</code>, which queries the pricing API directly and
needs no credentials. Generated from <code>scratch/azure_cost_report.py</code>; the
interactive version is the azure-hosting-plan canvas.
</footer>
</body></html>
"""

if __name__ == "__main__":
    print(HTML)
