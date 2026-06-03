import sys

file_path = "c:/Users/oriwe/.gemini/antigravity/scratch/pd35-mobile/android_Data_collection/PDDataCollect/app/src/main/java/com/pdcollect/app/data/DashboardSummaryStore.kt"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. DashboardMetrics
content = content.replace(
"""        val dailyStrideLength: List<TimePoint>,
        val dailyStrideSpeed: List<TimePoint>,
        val dailyTremorPower: List<TimePoint>,
        val dailyMarkers: List<EventMarker>,""",
"""        val dailyStrideLength: List<TimePoint>,
        val dailyStrideSpeed: List<TimePoint>,
        val dailyTremorPower: List<TimePoint>,
        val dailyAsymmetry: List<TimePoint>,
        val dailyMarkers: List<EventMarker>,""")

# 2. DailyComparisonDay
content = content.replace(
"""        val strideLength: List<TimePoint>,
        val strideSpeed: List<TimePoint>,
        val tremorPower: List<TimePoint>,
        val markers: List<EventMarker>""",
"""        val strideLength: List<TimePoint>,
        val strideSpeed: List<TimePoint>,
        val tremorPower: List<TimePoint>,
        val asymmetry: List<TimePoint>,
        val markers: List<EventMarker>""")

# 3. SensorSummary
content = content.replace(
"""    private data class SensorSummary(
        val strideLength: List<TimePoint>,
        val strideSpeed: List<TimePoint>,
        val tremorPower: List<TimePoint>,
        val maxStrideLength: Float,
        val maxStrideSpeed: Float,
        val maxTremorPower: Float
    )""",
"""    private data class SensorSummary(
        val strideLength: List<TimePoint>,
        val strideSpeed: List<TimePoint>,
        val tremorPower: List<TimePoint>,
        val asymmetry: List<TimePoint>,
        val maxStrideLength: Float,
        val maxStrideSpeed: Float,
        val maxTremorPower: Float,
        val maxAsymmetry: Float
    )""")

# 4. buildDashboardMetrics
content = content.replace(
"""            dailyTremorPower = clipTimePointsToCurrentTime(
                dateStr = dailySelection.first,
                points = readTimePoints(dailySelection.second, "tremor_power"),
                renderContext = renderContext
            ),
            dailyMarkers = clipMarkersToCurrentTime(""",
"""            dailyTremorPower = clipTimePointsToCurrentTime(
                dateStr = dailySelection.first,
                points = readTimePoints(dailySelection.second, "tremor_power"),
                renderContext = renderContext
            ),
            dailyAsymmetry = clipTimePointsToCurrentTime(
                dateStr = dailySelection.first,
                points = readTimePoints(dailySelection.second, "asymmetry"),
                renderContext = renderContext
            ),
            dailyMarkers = clipMarkersToCurrentTime(""")

# 5. buildDailyComparison
content = content.replace(
"""                tremorPower = clipTimePointsToCurrentTime(
                    dateStr = date,
                    points = readTimePoints(summary, "tremor_power"),
                    renderContext = renderContext
                ),
                markers = clipMarkersToCurrentTime(""",
"""                tremorPower = clipTimePointsToCurrentTime(
                    dateStr = date,
                    points = readTimePoints(summary, "tremor_power"),
                    renderContext = renderContext
                ),
                asymmetry = clipTimePointsToCurrentTime(
                    dateStr = date,
                    points = readTimePoints(summary, "asymmetry"),
                    renderContext = renderContext
                ),
                markers = clipMarkersToCurrentTime(""")

# 6. buildSummary (JSON writer)
content = content.replace(
"""                put("stride_length", writeTimePoints(merged.strideLength))
                put("stride_speed", writeTimePoints(merged.strideSpeed))
                put("tremor_power", writeTimePoints(merged.tremorPower))
                put("max_stride_length", merged.maxStrideLength.toDouble())
                put("max_stride_speed", merged.maxStrideSpeed.toDouble())
                put("max_tremor_power", merged.maxTremorPower.toDouble())
            } else if (existing != null) {
                put("sensor_scan_pos", existing.optLong("sensor_scan_pos", 0L))
                listOf("stride_length", "stride_speed", "tremor_power").forEach { key ->""",
"""                put("stride_length", writeTimePoints(merged.strideLength))
                put("stride_speed", writeTimePoints(merged.strideSpeed))
                put("tremor_power", writeTimePoints(merged.tremorPower))
                put("asymmetry", writeTimePoints(merged.asymmetry))
                put("max_stride_length", merged.maxStrideLength.toDouble())
                put("max_stride_speed", merged.maxStrideSpeed.toDouble())
                put("max_tremor_power", merged.maxTremorPower.toDouble())
                put("max_asymmetry", merged.maxAsymmetry.toDouble())
            } else if (existing != null) {
                put("sensor_scan_pos", existing.optLong("sensor_scan_pos", 0L))
                listOf("stride_length", "stride_speed", "tremor_power", "asymmetry").forEach { key ->""")

content = content.replace(
"""                put(
                    "max_tremor_power",
                    existing.optDouble("max_tremor_power", Double.NaN)
                        .takeIf { isValidTrendValue("max_tremor_power", it) } ?: 0.0
                )
            }""",
"""                put(
                    "max_tremor_power",
                    existing.optDouble("max_tremor_power", Double.NaN)
                        .takeIf { isValidTrendValue("max_tremor_power", it) } ?: 0.0
                )
                put(
                    "max_asymmetry",
                    existing.optDouble("max_asymmetry", Double.NaN)
                        .takeIf { isValidTrendValue("max_asymmetry", it) } ?: 0.0
                )
            }""")

# 7. IncrementalSensorResult
content = content.replace(
"""    private data class IncrementalSensorResult(
        val strideLength: List<TimePoint>,
        val strideSpeed: List<TimePoint>,
        val tremorPower: List<TimePoint>,
        val maxStrideLength: Float,
        val maxStrideSpeed: Float,
        val maxTremorPower: Float,
        val newScanPos: Long,
        val replacesExisting: Boolean = false
    )""",
"""    private data class IncrementalSensorResult(
        val strideLength: List<TimePoint>,
        val strideSpeed: List<TimePoint>,
        val tremorPower: List<TimePoint>,
        val asymmetry: List<TimePoint>,
        val maxStrideLength: Float,
        val maxStrideSpeed: Float,
        val maxTremorPower: Float,
        val maxAsymmetry: Float,
        val newScanPos: Long,
        val replacesExisting: Boolean = false
    )""")

# 8. computeSensorSummaryIncremental (empty instance)
content = content.replace(
"""        val empty = IncrementalSensorResult(
            emptyList(), emptyList(), emptyList(), 0f, 0f, 0f,
            newScanPos = startPos
        )""",
"""        val empty = IncrementalSensorResult(
            emptyList(), emptyList(), emptyList(), emptyList(), 0f, 0f, 0f, 0f,
            newScanPos = startPos
        )""")

# 9. computeSensorSummaryIncremental (PDAnalysisEngine result)
content = content.replace(
"""                    IncrementalSensorResult(
                        strideLength = analysis.stepLength.map { TimePoint(it.minuteOfDay, it.value) },
                        strideSpeed = analysis.speed.map { TimePoint(it.minuteOfDay, it.value) },
                        tremorPower = analysis.tremorPower.map { TimePoint(it.minuteOfDay, it.value) },
                        maxStrideLength = analysis.maxStepLength,
                        maxStrideSpeed = analysis.maxSpeed,
                        maxTremorPower = analysis.maxTremorPower,
                        newScanPos = sensorFile.length(),
                        replacesExisting = true
                    )""",
"""                    IncrementalSensorResult(
                        strideLength = analysis.stepLength.map { TimePoint(it.minuteOfDay, it.value) },
                        strideSpeed = analysis.speed.map { TimePoint(it.minuteOfDay, it.value) },
                        tremorPower = analysis.tremorPower.map { TimePoint(it.minuteOfDay, it.value) },
                        asymmetry = analysis.asymmetry.map { TimePoint(it.minuteOfDay, it.value) },
                        maxStrideLength = analysis.maxStepLength,
                        maxStrideSpeed = analysis.maxSpeed,
                        maxTremorPower = analysis.maxTremorPower,
                        maxAsymmetry = analysis.maxAsymmetry,
                        newScanPos = sensorFile.length(),
                        replacesExisting = true
                    )""")

# 10. computeSensorSummaryIncremental (legacy return)
content = content.replace(
"""        return IncrementalSensorResult(
            strideLength = stridePoints,
            strideSpeed = strideSpeedBuckets.mapIndexedNotNull { index, bucket ->
                bucket.meanOrNull()?.let { TimePoint(index * BIN_MINUTES + BIN_MINUTES / 2, it) }
            },
            tremorPower = tremorPoints,
            maxStrideLength = maxStrideLength,
            maxStrideSpeed = maxStrideSpeed,
            maxTremorPower = maxTremorPower,
            newScanPos = newScanPos
        )""",
"""        return IncrementalSensorResult(
            strideLength = stridePoints,
            strideSpeed = strideSpeedBuckets.mapIndexedNotNull { index, bucket ->
                bucket.meanOrNull()?.let { TimePoint(index * BIN_MINUTES + BIN_MINUTES / 2, it) }
            },
            tremorPower = tremorPoints,
            asymmetry = emptyList(), // Legacy parser doesn't compute gait asymmetry
            maxStrideLength = maxStrideLength,
            maxStrideSpeed = maxStrideSpeed,
            maxTremorPower = maxTremorPower,
            maxAsymmetry = 0f,
            newScanPos = newScanPos
        )""")

# 11. mergeSensorResults
content = content.replace(
"""        val existingMaxTremor = existing
            ?.optDouble("max_tremor_power", Double.NaN)
            ?.takeIf { isValidTrendValue("max_tremor_power", it) }
            ?.toFloat() ?: 0f

        return SensorSummary(
            strideLength    = merge(fresh.strideLength, "stride_length"),
            strideSpeed     = merge(fresh.strideSpeed,  "stride_speed"),
            tremorPower     = merge(fresh.tremorPower,  "tremor_power"),
            maxStrideLength = maxOf(existingMaxStride, fresh.maxStrideLength),
            maxStrideSpeed  = maxOf(existingMaxSpeed,  fresh.maxStrideSpeed),
            maxTremorPower  = maxOf(existingMaxTremor, fresh.maxTremorPower)
        )""",
"""        val existingMaxTremor = existing
            ?.optDouble("max_tremor_power", Double.NaN)
            ?.takeIf { isValidTrendValue("max_tremor_power", it) }
            ?.toFloat() ?: 0f
        val existingMaxAsymmetry = existing
            ?.optDouble("max_asymmetry", Double.NaN)
            ?.takeIf { isValidTrendValue("max_asymmetry", it) }
            ?.toFloat() ?: 0f

        return SensorSummary(
            strideLength    = merge(fresh.strideLength, "stride_length"),
            strideSpeed     = merge(fresh.strideSpeed,  "stride_speed"),
            tremorPower     = merge(fresh.tremorPower,  "tremor_power"),
            asymmetry       = merge(fresh.asymmetry,    "asymmetry"),
            maxStrideLength = maxOf(existingMaxStride, fresh.maxStrideLength),
            maxStrideSpeed  = maxOf(existingMaxSpeed,  fresh.maxStrideSpeed),
            maxTremorPower  = maxOf(existingMaxTremor, fresh.maxTremorPower),
            maxAsymmetry    = maxOf(existingMaxAsymmetry, fresh.maxAsymmetry)
        )""")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("DashboardSummaryStore.kt updated.")
