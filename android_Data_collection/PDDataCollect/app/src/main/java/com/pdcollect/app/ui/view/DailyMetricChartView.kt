package com.pdcollect.app.ui.view

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathEffect
import android.util.AttributeSet
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import com.pdcollect.app.data.DashboardSummaryStore
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class DailyMetricChartView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    data class ComparisonLine(
        val label: String,
        val points: List<DashboardSummaryStore.TimePoint>,
        val markers: List<DashboardSummaryStore.EventMarker> = emptyList()
    )

    private data class RenderSeries(
        val label: String,
        val isPrimary: Boolean,
        val points: List<DashboardSummaryStore.TimePoint>,
        val markers: List<DashboardSummaryStore.EventMarker>,
        val color: Int,
        val strokeWidth: Float,
        val pointRadius: Float,
        val pathEffect: PathEffect? = null
    )

    private var title = ""
    private var subtitle = "Blue solid = today to now, grey dashed = previous days"
    private var primaryLabel = "Today"
    private var unit = ""
    private var emptyHint = ""
    private var points: List<DashboardSummaryStore.TimePoint> = emptyList()
    private var comparisonLines: List<ComparisonLine> = emptyList()
    private var markers: List<DashboardSummaryStore.EventMarker> = emptyList()
    private var interactiveZoomEnabled = false

    private var zoomFactor = 1f
    private var scrollFraction = 0f
    private var activePointerId = MotionEvent.INVALID_POINTER_ID
    private var lastTouchX = 0f

    private val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#1A1C20")
        textSize = 36f
        typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD)
    }
    private val subtitlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#6F7280")
        textSize = 24f
    }
    private val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#E7E9EF")
        strokeWidth = 1.5f
    }
    private val axisPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#7E8595")
        textSize = 22f
        textAlign = Paint.Align.CENTER
    }
    private val valuePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#7E8595")
        textSize = 20f
        textAlign = Paint.Align.RIGHT
    }
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val pointPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val unitPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#6F7280")
        textSize = 20f
        textAlign = Paint.Align.RIGHT
    }
    private val markerLinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val markerLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#4E5565")
        textSize = 16f
        textAlign = Paint.Align.CENTER
    }
    private val markerDotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val legendPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#4E5565")
        textSize = 18f
    }
    private val emptyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#9AA0AE")
        textSize = 28f
        textAlign = Paint.Align.CENTER
    }

    private val scaleGestureDetector = ScaleGestureDetector(
        context,
        object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(detector: ScaleGestureDetector): Boolean {
                if (!interactiveZoomEnabled) return false
                val previousVisibleMinutes = visibleMinutes()
                zoomFactor = (zoomFactor * detector.scaleFactor).coerceIn(1f, MAX_ZOOM)
                adjustScrollForFocus(detector.focusX, previousVisibleMinutes)
                invalidate()
                return true
            }
        }
    )

    private val gestureDetector = GestureDetector(
        context,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onDoubleTap(e: MotionEvent): Boolean {
                if (!interactiveZoomEnabled) return false
                resetZoom()
                return true
            }
        }
    )

    fun setData(
        title: String,
        subtitle: String = "Blue solid = today to now, grey dashed = previous days",
        unit: String,
        points: List<DashboardSummaryStore.TimePoint>,
        comparisonLines: List<ComparisonLine> = emptyList(),
        markers: List<DashboardSummaryStore.EventMarker>,
        primaryLabel: String = "Today",
        emptyHint: String = ""
    ) {
        this.title = title
        this.subtitle = subtitle
        this.primaryLabel = primaryLabel
        this.unit = unit
        this.emptyHint = emptyHint
        this.points = points.sortedBy { it.minuteOfDay }
        this.comparisonLines = comparisonLines.map { line ->
            line.copy(
                points = line.points.sortedBy { it.minuteOfDay },
                markers = line.markers.sortedBy { it.minuteOfDay }
            )
        }
        this.markers = markers.sortedBy { it.minuteOfDay }
        invalidate()
    }

    fun setInteractiveZoomEnabled(enabled: Boolean) {
        interactiveZoomEnabled = enabled
        if (!enabled) {
            resetZoom()
        } else {
            invalidate()
        }
    }

    override fun performClick(): Boolean = super.performClick()

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!interactiveZoomEnabled) {
            return super.onTouchEvent(event)
        }

        gestureDetector.onTouchEvent(event)
        scaleGestureDetector.onTouchEvent(event)

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                parent?.requestDisallowInterceptTouchEvent(true)
                activePointerId = event.getPointerId(0)
                lastTouchX = event.x
                return true
            }

            MotionEvent.ACTION_MOVE -> {
                if (!scaleGestureDetector.isInProgress && zoomFactor > 1f) {
                    val pointerIndex = event.findPointerIndex(activePointerId)
                    if (pointerIndex >= 0) {
                        val x = event.getX(pointerIndex)
                        panBy(x - lastTouchX)
                        lastTouchX = x
                    }
                }
                return true
            }

            MotionEvent.ACTION_POINTER_UP -> {
                if (event.getPointerId(event.actionIndex) == activePointerId) {
                    val nextIndex = if (event.actionIndex == 0) 1 else 0
                    if (nextIndex < event.pointerCount) {
                        activePointerId = event.getPointerId(nextIndex)
                        lastTouchX = event.getX(nextIndex)
                    }
                }
            }

            MotionEvent.ACTION_UP -> {
                performClick()
                activePointerId = MotionEvent.INVALID_POINTER_ID
                parent?.requestDisallowInterceptTouchEvent(false)
                return true
            }

            MotionEvent.ACTION_CANCEL -> {
                activePointerId = MotionEvent.INVALID_POINTER_ID
                parent?.requestDisallowInterceptTouchEvent(false)
                return true
            }
        }

        return super.onTouchEvent(event)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        canvas.drawText(title, 28f, 42f, titlePaint)
        canvas.drawText(subtitle, 28f, 76f, subtitlePaint)

        val renderSeries = buildRenderableSeries()
        val nonEmptySeries = renderSeries.filter { it.points.isNotEmpty() }
        if (nonEmptySeries.isEmpty()) {
            val msg = emptyHint.ifBlank { "No daily traces available for the last 3 days" }
            val maxWidth = width - 56f
            drawWrappedText(canvas, msg, width / 2f, height / 2f - 14f, maxWidth, emptyPaint)
            return
        }

        val legendBottom = drawLegend(canvas, nonEmptySeries)

        val chartLeft = 90f
        val chartTop = legendBottom + if (interactiveZoomEnabled) 46f else 28f
        val chartRight = width - 28f
        val chartBottom = height - 72f
        val chartWidth = chartRight - chartLeft
        val chartHeight = chartBottom - chartTop

        val visibleMinutes = visibleMinutes()
        val windowStart = windowStartMinutes(visibleMinutes)
        val windowEnd = windowStart + visibleMinutes
        val visibleSeries = nonEmptySeries.map { series ->
            series.copy(points = pointsForWindow(series.points, windowStart, windowEnd))
        }.filter { it.points.isNotEmpty() }

        if (visibleSeries.isEmpty()) {
            val msg = "Zoomed beyond available samples. Double-tap to reset."
            drawWrappedText(canvas, msg, width / 2f, height / 2f - 14f, width - 56f, emptyPaint)
            return
        }

        val visiblePoints = visibleSeries.flatMap { it.points }
        val rawMinValue = visiblePoints.minOfOrNull { it.value } ?: 0f
        val rawMaxValue = visiblePoints.maxOfOrNull { it.value } ?: 1f
        val minValue = if (rawMinValue > 0f) rawMinValue * 0.9f else rawMinValue - (rawMaxValue - rawMinValue) * 0.1f
        val maxValue = max(rawMaxValue * 1.1f, minValue + 0.1f)
        val range = maxValue - minValue

        for (i in 0..4) {
            val y = chartTop + chartHeight * i / 4f
            val value = maxValue - range * i / 4f
            canvas.drawLine(chartLeft, y, chartRight, y, gridPaint)
            canvas.drawText(String.format(java.util.Locale.US, "%.2f", value), chartLeft - 10f, y + 6f, valuePaint)
        }

        for (i in 0..4) {
            val x = chartLeft + chartWidth * i / 4f
            val minute = windowStart + visibleMinutes * i / 4f
            canvas.drawLine(x, chartTop, x, chartBottom, gridPaint)
            canvas.drawText(formatMinuteLabel(minute), x, chartBottom + 34f, axisPaint)
        }
        canvas.drawText(unit, chartRight, chartTop - 12f, unitPaint)

        drawMarkers(
            canvas = canvas,
            series = renderSeries,
            chartLeft = chartLeft,
            chartTop = chartTop,
            chartBottom = chartBottom,
            chartWidth = chartWidth,
            windowStart = windowStart,
            windowEnd = windowEnd,
            visibleMinutes = visibleMinutes
        )

        visibleSeries.forEach { series ->
            linePaint.color = series.color
            linePaint.strokeWidth = series.strokeWidth
            linePaint.pathEffect = series.pathEffect
            pointPaint.color = series.color
            val path = Path()
            series.points.forEachIndexed { index, point ->
                val x = chartLeft + chartWidth * ((point.minuteOfDay - windowStart) / visibleMinutes)
                val y = chartBottom - ((point.value - minValue) / range) * chartHeight
                if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
                canvas.drawCircle(x, y, series.pointRadius, pointPaint)
            }
            canvas.drawPath(path, linePaint)
        }
        linePaint.pathEffect = null
    }

    private fun buildRenderableSeries(): List<RenderSeries> {
        val primary = movingAverage(points)
        val previousDaySeries = comparisonLines.mapIndexed { index, line ->
            RenderSeries(
                label = line.label,
                isPrimary = false,
                points = movingAverage(line.points),
                markers = line.markers,
                color = if (index == 0) PREVIOUS_DAY_COLOR else TWO_DAYS_AGO_COLOR,
                strokeWidth = 3.5f,
                pointRadius = 3.5f,
                pathEffect = DashPathEffect(floatArrayOf(10f, 8f), 0f)
            )
        }
        return listOf(
            RenderSeries(
                label = primaryLabel,
                isPrimary = true,
                points = primary,
                markers = markers,
                color = TODAY_COLOR,
                strokeWidth = 5f,
                pointRadius = 4.5f
            )
        ) + previousDaySeries
    }

    private fun drawLegend(canvas: Canvas, series: List<RenderSeries>): Float {
        var x = 28f
        val y = 98f
        var rowY = y
        val maxX = width - 28f
        series.forEach { item ->
            val labelWidth = legendPaint.measureText(item.label)
            val itemWidth = 28f + labelWidth + 18f
            if (x > 28f && x + itemWidth > maxX) {
                x = 28f
                rowY += 24f
            }
            linePaint.color = item.color
            linePaint.strokeWidth = item.strokeWidth
            linePaint.pathEffect = item.pathEffect
            canvas.drawLine(x, rowY - 5f, x + 18f, rowY - 5f, linePaint)
            pointPaint.color = item.color
            canvas.drawCircle(x + 9f, rowY - 5f, 4.5f, pointPaint)
            linePaint.pathEffect = null
            canvas.drawText(item.label, x + 28f, rowY, legendPaint)
            x += itemWidth
        }
        return rowY
    }

    private fun drawMarkers(
        canvas: Canvas,
        series: List<RenderSeries>,
        chartLeft: Float,
        chartTop: Float,
        chartBottom: Float,
        chartWidth: Float,
        windowStart: Float,
        windowEnd: Float,
        visibleMinutes: Float
    ) {
        data class MarkerPlacement(
            val x: Float,
            val marker: DashboardSummaryStore.EventMarker,
            val seriesColor: Int,
            val isPrimary: Boolean
        )

        val placements = series.flatMap { renderSeries ->
            renderSeries.markers
                .filter { it.minuteOfDay.toFloat() in windowStart..windowEnd }
                .map { marker ->
                    MarkerPlacement(
                        x = chartLeft + chartWidth * ((marker.minuteOfDay - windowStart) / visibleMinutes),
                        marker = marker,
                        seriesColor = renderSeries.color,
                        isPrimary = renderSeries.isPrimary
                    )
                }
        }.sortedBy { it.x }

        placements.forEachIndexed { index, placement ->
            markerLinePaint.color = markerColor(placement.seriesColor, placement.marker.type)
            markerLinePaint.strokeWidth = if (placement.marker.type == "medication") 3.5f else 2.5f
            markerLinePaint.pathEffect = if (placement.marker.type == "medication" && placement.isPrimary) {
                null
            } else {
                DashPathEffect(floatArrayOf(8f, 6f), 0f)
            }
            canvas.drawLine(placement.x, chartTop, placement.x, chartBottom, markerLinePaint)

            markerDotPaint.color = markerLinePaint.color
            canvas.drawCircle(placement.x, chartTop, 4f, markerDotPaint)

            if (interactiveZoomEnabled && placement.marker.type == "medication") {
                markerLabelPaint.color = placement.seriesColor
                val labelY = chartTop - 18f - (index % 2) * 18f
                canvas.drawText(formatMinuteLabel(placement.marker.minuteOfDay.toFloat()), placement.x, labelY, markerLabelPaint)
            }
        }
        markerLinePaint.pathEffect = null
    }

    private fun drawWrappedText(canvas: Canvas, text: String, cx: Float, startY: Float, maxWidth: Float, paint: Paint) {
        val words = text.split(" ")
        val lines = mutableListOf<String>()
        var current = ""
        for (word in words) {
            val candidate = if (current.isEmpty()) word else "$current $word"
            if (paint.measureText(candidate) <= maxWidth) {
                current = candidate
            } else {
                if (current.isNotEmpty()) lines += current
                current = word
            }
        }
        if (current.isNotEmpty()) lines += current
        val lineHeight = paint.textSize * 1.4f
        val totalHeight = lineHeight * lines.size
        var y = startY - totalHeight / 2f + paint.textSize
        for (line in lines) {
            canvas.drawText(line, cx, y, paint)
            y += lineHeight
        }
    }

    private fun movingAverage(points: List<DashboardSummaryStore.TimePoint>): List<DashboardSummaryStore.TimePoint> {
        if (points.size < 3) return points
        return points.indices.map { index ->
            var sum = 0f
            var count = 0
            for (sampleIndex in max(0, index - 1)..min(points.lastIndex, index + 1)) {
                sum += points[sampleIndex].value
                count++
            }
            DashboardSummaryStore.TimePoint(points[index].minuteOfDay, sum / count)
        }
    }

    private fun visibleMinutes(): Float = MINUTES_PER_DAY / zoomFactor

    private fun windowStartMinutes(visibleMinutes: Float): Float {
        val maxStart = (MINUTES_PER_DAY - visibleMinutes).coerceAtLeast(0f)
        return maxStart * scrollFraction
    }

    private fun resetZoom() {
        zoomFactor = 1f
        scrollFraction = 0f
        invalidate()
    }

    private fun pointsForWindow(
        points: List<DashboardSummaryStore.TimePoint>,
        windowStart: Float,
        windowEnd: Float
    ): List<DashboardSummaryStore.TimePoint> {
        return points.filter { it.minuteOfDay.toFloat() in windowStart..windowEnd }
    }

    private fun adjustScrollForFocus(focusX: Float, previousVisibleMinutes: Float) {
        val chartLeft = 90f
        val chartRight = width - 28f
        val chartWidth = (chartRight - chartLeft).coerceAtLeast(1f)
        val focusRatio = ((focusX - chartLeft) / chartWidth).coerceIn(0f, 1f)
        val previousStart = windowStartMinutes(previousVisibleMinutes)
        val focusMinute = previousStart + previousVisibleMinutes * focusRatio
        val newVisibleMinutes = visibleMinutes()
        val newStart = focusMinute - newVisibleMinutes * focusRatio
        val maxStart = (MINUTES_PER_DAY - newVisibleMinutes).coerceAtLeast(0f)
        scrollFraction = if (maxStart == 0f) 0f else (newStart / maxStart).coerceIn(0f, 1f)
    }

    private fun panBy(deltaX: Float) {
        if (zoomFactor <= 1f) return
        val chartWidth = (width - 118f).coerceAtLeast(1f)
        val visibleMinutes = visibleMinutes()
        val maxStart = (MINUTES_PER_DAY - visibleMinutes).coerceAtLeast(0f)
        if (maxStart == 0f) {
            scrollFraction = 0f
            return
        }
        val start = windowStartMinutes(visibleMinutes) - (deltaX / chartWidth) * visibleMinutes
        scrollFraction = (start / maxStart).coerceIn(0f, 1f)
        invalidate()
    }

    private fun formatMinuteLabel(minute: Float): String {
        val clampedMinute = minute.roundToInt().coerceIn(0, MINUTES_PER_DAY.toInt())
        val hour = clampedMinute / 60
        val minOfHour = clampedMinute % 60
        return String.format(java.util.Locale.US, "%02d:%02d", hour, minOfHour)
    }

    private fun markerColor(seriesColor: Int, type: String): Int {
        val alpha = if (type == "medication") 190 else 140
        return Color.argb(
            alpha,
            Color.red(seriesColor),
            Color.green(seriesColor),
            Color.blue(seriesColor)
        )
    }

    companion object {
        private const val MINUTES_PER_DAY = 24f * 60f
        private const val MAX_ZOOM = 6f
        private val TODAY_COLOR = Color.parseColor("#0D5BD7")
        private val PREVIOUS_DAY_COLOR = Color.parseColor("#9098A6")
        private val TWO_DAYS_AGO_COLOR = Color.parseColor("#C0C6D0")
    }
}
