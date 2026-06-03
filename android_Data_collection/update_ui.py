import sys

# 1. Update activity_main.xml
xml_path = "c:/Users/oriwe/.gemini/antigravity/scratch/pd35-mobile/android_Data_collection/PDDataCollect/app/src/main/res/layout/activity_main.xml"
with open(xml_path, "r", encoding="utf-8") as f:
    xml_content = f.read()

tremor_xml = """                <com.google.android.material.card.MaterialCardView
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    app:cardCornerRadius="24dp"
                    app:cardElevation="0dp"
                    app:cardBackgroundColor="@color/surface_container_low"
                    android:layout_marginBottom="16dp">

                    <com.pdcollect.app.ui.view.DailyMetricChartView
                        android:id="@+id/chartDailyTremorPower"
                        android:layout_width="match_parent"
                        android:layout_height="240dp"
                        android:padding="20dp" />
                </com.google.android.material.card.MaterialCardView>"""

asymmetry_xml = """                <com.google.android.material.card.MaterialCardView
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    app:cardCornerRadius="24dp"
                    app:cardElevation="0dp"
                    app:cardBackgroundColor="@color/surface_container_low"
                    android:layout_marginBottom="16dp">

                    <com.pdcollect.app.ui.view.DailyMetricChartView
                        android:id="@+id/chartDailyAsymmetry"
                        android:layout_width="match_parent"
                        android:layout_height="240dp"
                        android:padding="20dp" />
                </com.google.android.material.card.MaterialCardView>"""

if "chartDailyAsymmetry" not in xml_content:
    xml_content = xml_content.replace(tremor_xml, tremor_xml + "\n\n" + asymmetry_xml)
    with open(xml_path, "w", encoding="utf-8") as f:
        f.write(xml_content)


# 2. Update MainActivity.kt
main_path = "c:/Users/oriwe/.gemini/antigravity/scratch/pd35-mobile/android_Data_collection/PDDataCollect/app/src/main/java/com/pdcollect/app/ui/MainActivity.kt"
with open(main_path, "r", encoding="utf-8") as f:
    main_content = f.read()

main_content = main_content.replace(
"""        val (todayTremorPower, previousTremorPower) = dailyComparisonLines(metrics) { it.tremorPower }""",
"""        val (todayTremorPower, previousTremorPower) = dailyComparisonLines(metrics) { it.tremorPower }
        val (todayAsymmetry, previousAsymmetry) = dailyComparisonLines(metrics) { it.asymmetry }""")

main_content = main_content.replace(
"""            hasTodayData = todayStrideLength.isNotEmpty() || todayStrideSpeed.isNotEmpty() || todayTremorPower.isNotEmpty(),""",
"""            hasTodayData = todayStrideLength.isNotEmpty() || todayStrideSpeed.isNotEmpty() || todayTremorPower.isNotEmpty() || todayAsymmetry.isNotEmpty(),""")

main_content = main_content.replace(
"""            emptyHint = "Tremor data will appear once sensors are collecting"
        )""",
"""            emptyHint = "Tremor data will appear once sensors are collecting"
        )
        findViewById<DailyMetricChartView>(R.id.chartDailyAsymmetry).setData(
            title = "Gait Asymmetry",
            subtitle = dailySubtitle,
            unit = "%",
            points = todayAsymmetry,
            comparisonLines = previousAsymmetry,
            markers = todayMarkers,
            emptyHint = "Asymmetry data will appear once gait is detected"
        )""")

main_content = main_content.replace(
"""        findViewById<DailyMetricChartView>(R.id.chartDailyTremorPower).setOnClickListener {
            startActivity(ChartDetailActivity.intent(this, ChartDetailActivity.CHART_DAILY_TREMOR_POWER))
        }""",
"""        findViewById<DailyMetricChartView>(R.id.chartDailyTremorPower).setOnClickListener {
            startActivity(ChartDetailActivity.intent(this, ChartDetailActivity.CHART_DAILY_TREMOR_POWER))
        }
        findViewById<DailyMetricChartView>(R.id.chartDailyAsymmetry).setOnClickListener {
            startActivity(ChartDetailActivity.intent(this, ChartDetailActivity.CHART_DAILY_ASYMMETRY))
        }""")

main_content = main_content.replace(
"""            dailyTremorPower = emptyList(),""",
"""            dailyTremorPower = emptyList(),
            dailyAsymmetry = emptyList(),""")

main_content = main_content.replace(
"""            metrics.dailyTremorPower.isEmpty() &&""",
"""            metrics.dailyTremorPower.isEmpty() &&
            metrics.dailyAsymmetry.isEmpty() &&""")

with open(main_path, "w", encoding="utf-8") as f:
    f.write(main_content)


# 3. Update ChartDetailActivity.kt
detail_path = "c:/Users/oriwe/.gemini/antigravity/scratch/pd35-mobile/android_Data_collection/PDDataCollect/app/src/main/java/com/pdcollect/app/ui/ChartDetailActivity.kt"
with open(detail_path, "r", encoding="utf-8") as f:
    detail_content = f.read()

detail_content = detail_content.replace(
"""            CHART_DAILY_STRIDE_SPEED,
            CHART_DAILY_TREMOR_POWER -> {""",
"""            CHART_DAILY_STRIDE_SPEED,
            CHART_DAILY_TREMOR_POWER,
            CHART_DAILY_ASYMMETRY -> {""")

detail_content = detail_content.replace(
"""            CHART_DAILY_TREMOR_POWER -> bindDailyChart(
                metrics,
                title = "Tremor Window Power",
                unit = "%",
                emptyHint = "Tremor data will appear once sensors are collecting"
            ) { it.tremorPower }""",
"""            CHART_DAILY_TREMOR_POWER -> bindDailyChart(
                metrics,
                title = "Tremor Window Power",
                unit = "%",
                emptyHint = "Tremor data will appear once sensors are collecting"
            ) { it.tremorPower }
            CHART_DAILY_ASYMMETRY -> bindDailyChart(
                metrics,
                title = "Gait Asymmetry",
                unit = "%",
                emptyHint = "Asymmetry data will appear once gait is detected"
            ) { it.asymmetry }""")

detail_content = detail_content.replace(
"""        const val CHART_DAILY_TREMOR_POWER = "daily_tremor_power" """.strip(),
"""        const val CHART_DAILY_TREMOR_POWER = "daily_tremor_power"
        const val CHART_DAILY_ASYMMETRY = "daily_asymmetry" """.strip())

with open(detail_path, "w", encoding="utf-8") as f:
    f.write(detail_content)

print("UI files updated.")
