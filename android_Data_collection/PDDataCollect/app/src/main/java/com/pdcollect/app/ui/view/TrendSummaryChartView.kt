package com.pdcollect.app.ui.view

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.util.AttributeSet
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import androidx.core.content.ContextCompat
import com.pdcollect.app.R
import com.pdcollect.app.data.DashboardSummaryStore
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max

class TrendSummaryChartView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private var title = ""
    private var subtitle = ""
    private var emptyHint = ""
    private var series: List<DashboardSummaryStore.TrendSeries> = emptyList()
    private var interactiveZoomEnabled = false

    private var zoomFactor = 1f
    private var scrollFraction = 0f
    private var activePointerId = MotionEvent.INVALID_POINTER_ID
    private var lastTouchX = 0f

    // The 3 brand hues double as a categorical palette for however many trend
    // series are plotted (was 3 unrelated Material colors).
    private val palette = listOf(
        ContextCompat.getColor(context, R.color.blue),
        ContextCompat.getColor(context, R.color.orange),
        ContextCompat.getColor(context, R.color.purple)
    )

    private val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#1A1C20")
        textSize = 36f
        typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD)
    }
    private val subtitlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#6F7280")
        textSize = 22f
    }
    private val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#E7E9EF")
        strokeWidth = 1.5f
    }
    private val axisPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#7E8595")
        textSize = 20f
        textAlign = Paint.Align.CENTER
    }
    private val legendPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#4E5565")
        textSize = 22f
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
                val labelCount = currentLabelCount()
                val previousVisibleSpan = visibleSpan(labelCount)
                zoomFactor = (zoomFactor * detector.scaleFactor).coerceIn(1f, MAX_ZOOM)
                adjustScrollForFocus(detector.focusX, labelCount, previousVisibleSpan)
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

    fun setSeries(
        title: String,
        subtitle: String,
        series: List<DashboardSummaryStore.TrendSeries>,
        emptyHint: String = ""
    ) {
        this.title = title
        this.subtitle = subtitle
        this.emptyHint = emptyHint
        this.series = series
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
                        panBy(x - lastTouchX, currentLabelCount())
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

        val nonEmptySeries = series.map { trendSeries ->
            trendSeries.copy(points = trendSeries.points.filter { it.value.isFinite() && it.value in -1e6f..1e6f })
        }.filter { it.points.isNotEmpty() }
        if (nonEmptySeries.isEmpty()) {
            val msg = emptyHint.ifBlank { "No long-term trend data yet" }
            drawWrappedText(canvas, msg, width / 2f, height / 2f - 14f, width - 56f)
            return
        }

        val xLabels = nonEmptySeries.flatMap { it.points.map { point -> point.label } }.distinct().sorted()
        if (xLabels.isEmpty()) {
            val msg = emptyHint.ifBlank { "No long-term trend data yet" }
            drawWrappedText(canvas, msg, width / 2f, height / 2f - 14f, width - 56f)
            return
        }

        val chartLeft = 72f
        val chartTop = 110f
        val chartRight = width - 28f
        val chartBottom = height - 72f
        val chartWidth = chartRight - chartLeft
        val chartHeight = chartBottom - chartTop

        val visibleSpan = visibleSpan(xLabels.size)
        val windowStart = windowStartIndex(xLabels.size, visibleSpan)
        val windowEnd = windowStart + visibleSpan

        for (i in 0..4) {
            val y = chartTop + chartHeight * i / 4f
            canvas.drawLine(chartLeft, y, chartRight, y, gridPaint)
        }

        for (i in 0..4) {
            val ratio = i / 4f
            val x = chartLeft + chartWidth * ratio
            val labelIndex = (windowStart + visibleSpan * ratio).toInt().coerceIn(0, xLabels.lastIndex)
            canvas.drawLine(x, chartTop, x, chartBottom, gridPaint)
            canvas.drawText(xLabels[labelIndex].takeLast(5), x, chartBottom + 30f, axisPaint)
        }

        drawSeries(
            canvas = canvas,
            nonEmptySeries = nonEmptySeries,
            xLabels = xLabels,
            chartLeft = chartLeft,
            chartTop = chartTop,
            chartRight = chartRight,
            chartBottom = chartBottom,
            chartWidth = chartWidth,
            chartHeight = chartHeight,
            windowStart = windowStart,
            windowEnd = windowEnd,
            visibleSpan = visibleSpan
        )
    }

    private fun drawSeries(
        canvas: Canvas,
        nonEmptySeries: List<DashboardSummaryStore.TrendSeries>,
        xLabels: List<String>,
        chartLeft: Float,
        chartTop: Float,
        chartRight: Float,
        chartBottom: Float,
        chartWidth: Float,
        chartHeight: Float,
        windowStart: Float,
        windowEnd: Float,
        visibleSpan: Float
    ) {
        nonEmptySeries.forEachIndexed { index, trendSeries ->
            val color = palette[index % palette.size]
            val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = color
                strokeWidth = 4.5f
                style = Paint.Style.STROKE
                strokeCap = Paint.Cap.ROUND
                strokeJoin = Paint.Join.ROUND
            }
            val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = color
                style = Paint.Style.FILL
            }

            val pointIndexes = trendSeries.points.mapNotNull { point ->
                val xIndex = xLabels.indexOf(point.label)
                if (xIndex < 0 || xIndex.toFloat() !in windowStart..windowEnd) null else xIndex to point
            }
            if (pointIndexes.isEmpty()) return@forEachIndexed

            val values = pointIndexes.map { it.second.value }
            val minValue = values.minOrNull() ?: 0f
            val maxValue = (values.maxOrNull() ?: 1f).let { if (it == minValue) it + 1f else it }
            val range = maxValue - minValue
            val linePath = Path()

            pointIndexes.forEachIndexed { pointIndex, (xIndex, point) ->
                val x = if (visibleSpan == 0f) {
                    chartLeft + chartWidth / 2f
                } else {
                    chartLeft + chartWidth * ((xIndex - windowStart) / visibleSpan)
                }
                val y = chartBottom - ((point.value - minValue) / range) * chartHeight
                if (pointIndex == 0) linePath.moveTo(x, y) else linePath.lineTo(x, y)
                canvas.drawCircle(x, y, 5f, dotPaint)
            }
            canvas.drawPath(linePath, strokePaint)

            val legendY = chartTop - 14f + index * 24f
            canvas.drawCircle(chartRight - 180f, legendY - 6f, 6f, dotPaint)
            canvas.drawText("${trendSeries.name} (${trendSeries.unit})", chartRight - 166f, legendY, legendPaint)
        }
    }

    private fun drawWrappedText(canvas: Canvas, text: String, cx: Float, startY: Float, maxWidth: Float) {
        val words = text.split(" ")
        val lines = mutableListOf<String>()
        var current = ""
        for (word in words) {
            val candidate = if (current.isEmpty()) word else "$current $word"
            if (emptyPaint.measureText(candidate) <= maxWidth) {
                current = candidate
            } else {
                if (current.isNotEmpty()) lines += current
                current = word
            }
        }
        if (current.isNotEmpty()) lines += current
        val lineHeight = emptyPaint.textSize * 1.4f
        val totalHeight = lineHeight * lines.size
        var y = startY - totalHeight / 2f + emptyPaint.textSize
        for (line in lines) {
            canvas.drawText(line, cx, y, emptyPaint)
            y += lineHeight
        }
    }

    private fun currentLabelCount(): Int {
        return series.flatMap { trendSeries -> trendSeries.points.map { it.label } }.distinct().size
    }

    private fun visibleSpan(labelCount: Int): Float {
        if (labelCount <= 1) return 1f
        val totalSpan = (labelCount - 1).toFloat()
        return max(1f, totalSpan / zoomFactor)
    }

    private fun windowStartIndex(labelCount: Int, visibleSpan: Float): Float {
        val maxStart = max(0f, (labelCount - 1).toFloat() - visibleSpan)
        return maxStart * scrollFraction
    }

    private fun adjustScrollForFocus(focusX: Float, labelCount: Int, previousVisibleSpan: Float) {
        if (labelCount <= 1) {
            scrollFraction = 0f
            return
        }
        val chartLeft = 72f
        val chartRight = width - 28f
        val chartWidth = (chartRight - chartLeft).coerceAtLeast(1f)
        val focusRatio = ((focusX - chartLeft) / chartWidth).coerceIn(0f, 1f)
        val previousStart = windowStartIndex(labelCount, previousVisibleSpan)
        val focusIndex = previousStart + previousVisibleSpan * focusRatio
        val newVisibleSpan = visibleSpan(labelCount)
        val newStart = focusIndex - newVisibleSpan * focusRatio
        val maxStart = max(0f, (labelCount - 1).toFloat() - newVisibleSpan)
        scrollFraction = if (maxStart == 0f) 0f else (newStart / maxStart).coerceIn(0f, 1f)
    }

    private fun panBy(deltaX: Float, labelCount: Int) {
        if (zoomFactor <= 1f || labelCount <= 1) return
        val chartWidth = (width - 100f).coerceAtLeast(1f)
        val visibleSpan = visibleSpan(labelCount)
        val maxStart = max(0f, (labelCount - 1).toFloat() - visibleSpan)
        if (maxStart == 0f) {
            scrollFraction = 0f
            return
        }
        val start = windowStartIndex(labelCount, visibleSpan) - (deltaX / chartWidth) * visibleSpan
        scrollFraction = (start / maxStart).coerceIn(0f, 1f)
        invalidate()
    }

    private fun resetZoom() {
        zoomFactor = 1f
        scrollFraction = 0f
        invalidate()
    }

    companion object {
        private const val MAX_ZOOM = 6f
    }
}
