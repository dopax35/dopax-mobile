#!/usr/bin/env python3
"""
Where the daily archive size actually comes from.

Row formats are taken from the shipping code, not assumed:

  Android  PDCollectService.bufferReading()  ->  sensors.csv
           timestamp_ns + accel xyz + gyro xyz + MAG xyz  = 10 fields
           floats via Kotlin append(Float) = Float.toString(), variable length
           50 Hz (Constants.SENSOR_DELAY_US = 20_000), continuous 24/7

  iOS      SensorReading.csvRow             ->  passive_sensors.csv
           timestamp_ns + accel xyz + gyro xyz            = 7 fields
           floats via String(format: "%.6f"), fixed width
           50 Hz (PassiveSensorService.hz), duty cycle depends on keep-alive

Both ZIP with default deflate (level 6). No downsampling in either write path:
Android changelog 74 deliberately restored full fidelity.

    python3 scratch/why_storage.py
"""

HZ = 50
SEC_PER_DAY = 86_400

# Field widths in bytes, measured against the real format strings.
TS_NS = 19          # "1723889025123456789" epoch nanoseconds, as an integer
IOS_FLOAT = 9       # "%.6f" on a value under 10, e.g. "-0.123456"
AND_FLOAT = 10      # Float.toString(), e.g. "-0.61356354"; magnetometer shorter
NEWLINE = 1

# Deflate on monotonic timestamps plus noisy decimal floats. Timestamps compress
# hard, mantissa digits barely compress at all. 4x is the optimistic end of what
# level 6 achieves on this shape of data.
ZIP_RATIO = 4.0


def row_bytes(fields, width):
    """fields numeric columns: one timestamp, the rest floats, comma separated."""
    return TS_NS + (fields - 1) * width + (fields - 1) + NEWLINE


def mb(b):
    return b / 1024 / 1024


def gb(b):
    return b / 1024 / 1024 / 1024


print("=" * 78)
print("ONE DAY OF PASSIVE IMU, PER PARTICIPANT")
print("=" * 78)

rows = HZ * SEC_PER_DAY
print(f"  {HZ} Hz x {SEC_PER_DAY:,} s = {rows:,} rows per participant per day")
print(f"  which is {rows * 365 / 1e9:.2f} billion samples per participant per year\n")

for label, fields, width in (("Android  sensors.csv (10 cols, incl. magnetometer)", 10, AND_FLOAT),
                             ("iOS      passive_sensors.csv (7 cols)", 7, IOS_FLOAT)):
    rb = row_bytes(fields, width)
    raw = rows * rb
    print(f"  {label}")
    print(f"      {rb} bytes/row -> {mb(raw):,.0f} MB/day raw"
          f" -> ~{mb(raw / ZIP_RATIO):,.0f} MB/day zipped")

print("\n" + "=" * 78)
print("HOW MUCH OF THAT ROW IS ACTUAL INFORMATION")
print("=" * 78)
and_row = row_bytes(10, AND_FLOAT)
# float32 holds more precision than a 6-decimal sensor reading needs; the
# timestamp is a fixed 20 ms step, so a delta needs about a byte.
raw_binary = 9 * 4 + 1
# Columnar + zstd with byte-split floats and delta-encoded timestamps. Float
# mantissas stay noisy and never compress well, which is why this is ~2x rather
# than the 10x that "switch to Parquet" claims usually assume.
columnar = 14
zipped_csv = and_row / ZIP_RATIO
print(f"  Android CSV row, uncompressed          {and_row:>5.0f} bytes")
print(f"  the same row zipped                    {zipped_csv:>5.0f} bytes")
print(f"  raw float32 + delta timestamp          {raw_binary:>5.0f} bytes"
      f"   <- WORSE than zipped CSV")
print(f"  columnar (float32 + delta ts + zstd)   {columnar:>5.0f} bytes")
print(f"\n  So the fair comparison is zipped CSV against a compressed columnar")
print(f"  format, which is about {zipped_csv / columnar:.1f}x — not the 3.2x that the")
print(f"  uncompressed row sizes suggest. Deflate already recovers most of the")
print(f"  waste in the text encoding.")

print("\n" + "=" * 78)
print("THE THREE REASONS IT IS BIG, IN ORDER OF SIZE")
print("=" * 78)

raw_and = rows * and_row
zip_and = raw_and / ZIP_RATIO

print("\n  1. 24/7 continuous collection at 50 Hz")
print(f"     Full day:            ~{mb(zip_and):>6,.0f} MB/day zipped")
for hours, why in ((16, "drop the sleeping hours"),
                   (12, "waking hours only"),
                   (4, "four one-hour measurement windows")):
    frac = hours / 24
    print(f"     {hours:>2}h/day  {why:<34} ~{mb(zip_and * frac):>6,.0f} MB/day"
          f"   -{(1 - frac) * 100:>2.0f}%")

print("\n  2. Magnetometer is written on Android and not on iOS")
a10, a7 = row_bytes(10, AND_FLOAT), row_bytes(7, AND_FLOAT)
print(f"     10 columns {a10} B/row vs 7 columns {a7} B/row"
      f"  -> dropping it saves {(1 - a7 / a10) * 100:.0f}% of every Android row")
print("     iOS reads the magnetometer and discards it, so no cross-platform")
print("     analysis can use the Android values at all.")

print("\n  3. CSV text instead of a compressed columnar format")
print(f"     About {zipped_csv / columnar:.1f}x, and it costs a change to every reader and")
print("     every analysis script. The smallest of the three levers by far, and")
print("     the only one that is purely an engineering change.")

print("\n" + "=" * 78)
print("WHAT THE SAMPLING RATE IS ACTUALLY FOR")
print("=" * 78)
print("  PDAlgorithms.tremorPowerRatio analyses the 3-12 Hz band.")
print("  Nyquist puts the floor for 12 Hz at 24 Hz, so 50 Hz is the right rate")
print("  WHILE MEASURING. It is not evidence that 50 Hz is needed for all 86,400")
print("  seconds of every day, most of which is a phone lying on a table.")

print("\n" + "=" * 78)
print("COMBINED EFFECT ON THE AZURE BILL, 43 PARTICIPANTS")
print("=" * 78)
try:
    from azure_cost_report import REGIONS, storage, fixed, egress, DPM, ADHERENCE
    IL = REGIONS["israelcentral"]
    base = fixed(IL, 43)["total"]
    for label, gbpd in (("current model assumption", 0.40),
                        ("drop magnetometer (Android)", 0.40 * 0.72),
                        ("+ waking hours only (12h)", 0.40 * 0.72 * 0.50),
                        ("+ binary/columnar encoding", 0.40 * 0.72 * 0.50 * 0.55)):
        st, held = storage(IL, 43, 12, gbpd=gbpd)
        eg = egress(IL, 43)[0]
        print(f"  {label:<30}{gbpd:>5.2f} GB/day  "
              f"month-12 total ${base + st + eg:>6.2f}/mo   archive {held/1024:>5.1f} TB")
except ImportError:
    print("  (run from scratch/ so azure_cost_report is importable)")
