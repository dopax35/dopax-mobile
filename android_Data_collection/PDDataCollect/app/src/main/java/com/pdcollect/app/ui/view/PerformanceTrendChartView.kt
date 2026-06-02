package com.pdcollect.app.ui.view

import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.View
import kotlin.math.abs
import kotlin.math.max

/**
 * PerformanceTrendChartView — Premium dual-series canvas chart for the DopaX dashboard.
 *
 * Series 1 (primary):  Smooth line chart (e.g., TMT Time in ms or Tapping Bias)
 * Series 2 (optional): Dot overlay (e.g., Error Count on a secondary scale)
 *
 * Supports multiple data points per calendar day (plotted side-by-side within the day slot).
 */
class PerformanceTrendChartView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null, defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    data class ChartPoint(val dateLabel: String, val primary: Float, val secondary: Float? = null)

    // ── Data ──────────────────────────────────────────────────────────────────
    private var points: List<ChartPoint> = emptyList()
    private var label1: String = ""
    private var label2: String? = null
    private var showNegative = false  // for bias chart (negative values)

    // ── Paints ────────────────────────────────────────────────────────────────
    private val primaryLinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#00B0FF")   // Cyan 500
        strokeWidth = 5f
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val primaryFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val primaryDotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#00B0FF")
        style = Paint.Style.FILL
    }
    private val secondaryDotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FF5252")   // Red accent
        style = Paint.Style.FILL
    }
    private val secondaryDotBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 3f
    }
    private val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#F5F5F5")
        strokeWidth = 1.5f
        style = Paint.Style.STROKE
    }
    private val axisLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#757575")
        textSize = 28f
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
    }
    private val valueLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#9E9E9E")
        textSize = 26f
        textAlign = Paint.Align.CENTER
    }
    private val zeroLinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#E0E0E0")
        strokeWidth = 3f
        style = Paint.Style.STROKE
    }

    private val fillPath = Path()
    private val linePath = Path()
    private var xPositions = FloatArray(0)
    private var yPositions = FloatArray(0)
    private val emptyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#BDBDBD")
        textSize = 34f
        textAlign = Paint.Align.CENTER
    }

    // ── Layout constants ──────────────────────────────────────────────────────
    private val paddingLeft = 110f
    private val paddingRight = 110f
    private val paddingTop = 80f
    private val paddingBottom = 80f

    private val rightAxisLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FF5252")
        textSize = 26f
        textAlign = Paint.Align.LEFT
        typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
    }

    // ── Public API ────────────────────────────────────────────────────────────

    fun setData(
        data: List<ChartPoint>,
        primaryLabel: String,
        secondaryLabel: String? = null,
        showNegativeAxis: Boolean = false
    ) {
        points = data
        label1 = primaryLabel
        label2 = secondaryLabel
        showNegative = showNegativeAxis
        updatePaths()
        invalidate()
    }

    fun getChartData(): List<ChartPoint> = points
    fun getPrimaryLabel(): String = label1
    fun getSecondaryLabel(): String? = label2
    fun getShowNegativeAxis(): Boolean = showNegative

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        updatePaths()
    }

    private fun updatePaths() {
        if (points.isEmpty() || width == 0 || height == 0) return

        val chartLeft = paddingLeft
        val chartRight = width - paddingRight
        val chartTop = paddingTop
        val chartBottom = height - paddingBottom
        val chartW = chartRight - chartLeft
        val chartH = chartBottom - chartTop

        val minPrimary = if (showNegative) (points.minOfOrNull { it.primary } ?: 0f).coerceAtMost(0f)
                         else 0f
        val maxPrimary = (points.maxOfOrNull { it.primary } ?: 1f).coerceAtLeast(1f)
        val primaryRange = (maxPrimary - minPrimary).coerceAtLeast(1f)

        val uniqueDates = points.map { it.dateLabel }.distinct()
        val dateSlotW = chartW / uniqueDates.size.coerceAtLeast(1).toFloat()

        if (xPositions.size != points.size) {
            xPositions = FloatArray(points.size)
            yPositions = FloatArray(points.size)
        }

        val countPerDate = mutableMapOf<String, Int>()
        points.forEach { countPerDate[it.dateLabel] = (countPerDate[it.dateLabel] ?: 0) + 1 }
        val indexPerDate = mutableMapOf<String, Int>()

        for ((i, pt) in points.withIndex()) {
            val dateIdx = uniqueDates.indexOf(pt.dateLabel)
            val subIdx = indexPerDate[pt.dateLabel] ?: 0
            indexPerDate[pt.dateLabel] = subIdx + 1

            val slotStart = chartLeft + dateIdx * dateSlotW
            val subSpacing = dateSlotW / ((countPerDate[pt.dateLabel] ?: 1) + 1)
            xPositions[i] = slotStart + subSpacing * (subIdx + 1)
            yPositions[i] = chartBottom - ((pt.primary - minPrimary) / primaryRange) * chartH
        }

        linePath.reset()
        fillPath.reset()

        if (points.size >= 2) {
            // Cubic Spline interpolation with control points
            linePath.moveTo(xPositions[0], yPositions[0])
            for (i in 0 until xPositions.size - 1) {
                val x1 = xPositions[i]
                val y1 = yPositions[i]
                val x2 = xPositions[i+1]
                val y2 = yPositions[i+1]

                val dx = x2 - x1
                val cp1x = x1 + dx / 2.5f
                val cp2x = x2 - dx / 2.5f

                linePath.cubicTo(cp1x, y1, cp2x, y2, x2, y2)
            }

            fillPath.set(linePath)
            fillPath.lineTo(xPositions.last(), chartBottom)
            fillPath.lineTo(xPositions.first(), chartBottom)
            fillPath.close()

            primaryFillPaint.shader = LinearGradient(
                0f, chartTop, 0f, chartBottom,
                Color.parseColor("#4400B0FF"), Color.TRANSPARENT,
                Shader.TileMode.CLAMP
            )
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (points.isEmpty()) {
            drawEmptyState(canvas)
            return
        }

        val chartLeft = paddingLeft
        val chartRight = width - paddingRight
        val chartTop = paddingTop
        val chartBottom = height - paddingBottom
        val chartW = chartRight - chartLeft
        val chartH = chartBottom - chartTop

        val minPrimary = if (showNegative) (points.minOfOrNull { it.primary } ?: 0f).coerceAtMost(0f)
                         else 0f
        val maxPrimary = (points.maxOfOrNull { it.primary } ?: 1f).coerceAtLeast(1f)
        val primaryRange = maxPrimary - minPrimary

        val maxSecondary = (points.mapNotNull { it.secondary }.maxOrNull() ?: 1f).coerceAtLeast(1f)

        // ── Grid & Axes ────────────────────────────────────────────────────
        for (g in 0..4) {
            val gy = chartTop + chartH * g / 4f
            canvas.drawLine(chartLeft, gy, chartRight, gy, gridPaint)
            
            // Left Axis (Primary)
            val pVal = minPrimary + primaryRange * (4 - g) / 4f
            val pLabel = if (pVal >= 1000) "${(pVal/1000).toInt()}k" else pVal.toInt().toString()
            canvas.drawText(pLabel, chartLeft - 16f, gy + 10f, valueLabelPaint.apply { textAlign = Paint.Align.RIGHT })

            // Right Axis (Secondary - Errors)
            if (label2 != null) {
                val sVal = maxSecondary * (4 - g) / 4f
                canvas.drawText(sVal.toInt().toString(), chartRight + 16f, gy + 10f, rightAxisLabelPaint)
            }
        }

        // ── Drawing Paths ───────────────────────────────────────────────────
        if (points.size >= 2) {
            canvas.drawPath(fillPath, primaryFillPaint)
            canvas.drawPath(linePath, primaryLinePaint)
        }

        // ── Dots & Labels ──────────────────────────────────────────────
        for ((i, pt) in points.withIndex()) {
            val x = xPositions[i]
            val y = yPositions[i]
            
            // Primary Dot
            canvas.drawCircle(x, y, 10f, primaryDotPaint)
            canvas.drawCircle(x, y, 6f, secondaryDotBorderPaint)

            // Secondary Value (Plotted against right axis)
            if (pt.secondary != null) {
                val secY = chartBottom - (pt.secondary / maxSecondary) * chartH
                canvas.drawCircle(x, secY, 12f, secondaryDotPaint)
                canvas.drawCircle(x, secY, 12f, secondaryDotBorderPaint)
            }
        }

        // ── Axis Titles ─────────────────────────────────────────────
        canvas.drawText(label1, chartLeft, chartTop - 24f, axisLabelPaint.apply { textAlign = Paint.Align.LEFT })
        label2?.let { 
            canvas.drawText(it, chartRight, chartTop - 24f, rightAxisLabelPaint.apply { textAlign = Paint.Align.RIGHT })
        }

        // ── X-Axis Date Labels ─────────────────────────────────────────────
        val uniqueDates = points.map { it.dateLabel }.distinct()
        val chartW_axis = width - paddingLeft - paddingRight
        val dateSlotW = chartW_axis / uniqueDates.size.coerceAtLeast(1).toFloat()
        val step = (uniqueDates.size / 6).coerceAtLeast(1)
        val chartBottomWithPadding = height - paddingBottom
        for ((i, date) in uniqueDates.withIndex()) {
            if (i % step == 0 || i == uniqueDates.size - 1) {
                val slotCx = paddingLeft + i * dateSlotW + dateSlotW / 2f
                val label = date.takeLast(5)
                canvas.drawText(label, slotCx, chartBottomWithPadding + 48f, axisLabelPaint.apply { textAlign = Paint.Align.CENTER })
            }
        }
    }

    private fun drawEmptyState(canvas: Canvas) {
        canvas.drawText("No trends captured yet", width / 2f, height / 2f, emptyPaint)
    }
}
