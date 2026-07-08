package com.pdcollect.app.ui.view

import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.View
import androidx.core.content.ContextCompat
import com.pdcollect.app.R
import kotlin.math.cos
import kotlin.math.sin

/**
 * RadarChartView — 6-axis hexagonal symptom chart with dual-layer rendering.
 *
 * Axes:  Motor | Coord | Cognitive | Severity | HRV RMSSD | Tremor
 *
 * Blue layer  = current day's data  (setCurrentData)
 * Gray layer  = 30-day average      (setAverageData)
 * setData()   = legacy, sets current only (5-element arrays padded to 6)
 */
class RadarChartView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null, defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private val N_AXES = 6
    private val ANGLE_STEP = 360.0 / N_AXES

    private val axisLabels = arrayOf("Motor", "Coord", "Cognitive", "Severity", "HRV", "Tremor")

    /** Current performance (blue). Values 0.0 – 1.0 */
    private var currentData  = FloatArray(N_AXES) { 0.5f }
    /** 30-day average (gray). Values 0.0 – 1.0 */
    private var averageData  = FloatArray(N_AXES) { 0.5f }
    private var hasAverage   = false

    // ── Paints ────────────────────────────────────────────────────────────────

    private val webPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.divider)
        strokeWidth = 1.5f
        style = Paint.Style.STROKE
    }
    private val axisPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.gray_30)
        strokeWidth = 1f
        style = Paint.Style.STROKE
    }

    // Current (brand blue) fill + stroke
    private val currentFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.blue)
        style = Paint.Style.FILL
        alpha = 100
    }
    private val currentStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.blue_dark)
        strokeWidth = 4f
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
    }

    // Average (gray) fill + stroke
    private val avgFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.gray_50)
        style = Paint.Style.FILL
        alpha = 55
    }
    private val avgStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.black_70)
        strokeWidth = 2.5f
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
        pathEffect = DashPathEffect(floatArrayOf(10f, 5f), 0f)
    }

    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.black_70)
        textSize = 36f
        textAlign = Paint.Align.CENTER
    }
    private val subLabelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.gray_50)
        textSize = 28f
        textAlign = Paint.Align.CENTER
    }

    // ── Dot paints for current data ───────────────────────────────────────────
    private val currentDotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.blue)
        style = Paint.Style.FILL
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /** Set today's values. Array must be exactly 6 floats [0,1]. */
    fun setCurrentData(points: FloatArray) {
        if (points.size == N_AXES) { currentData = points; invalidate() }
    }

    /** Set 30-day average values. Array must be exactly 6 floats [0,1]. */
    fun setAverageData(points: FloatArray) {
        if (points.size == N_AXES) { averageData = points; hasAverage = true; invalidate() }
    }

    /** Legacy 5-element setData — pads Tremor=0 automatically. */
    fun setData(points: FloatArray) {
        val padded = FloatArray(N_AXES)
        for (i in 0 until minOf(points.size, N_AXES)) padded[i] = points[i]
        currentData = padded
        invalidate()
    }

    fun getCurrentData(): FloatArray = currentData
    fun getAverageData(): FloatArray = averageData


    // ── Drawing ───────────────────────────────────────────────────────────────

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val cx = width / 2f
        val cy = height / 2f
        val radius = minOf(width, height) / 2f * 0.60f

        // Web rings
        for (ring in 1..4) {
            drawHexagon(canvas, cx, cy, radius * ring / 4f, webPaint)
        }

        // Axis spokes + labels
        for (i in 0 until N_AXES) {
            val angle = Math.toRadians(i * ANGLE_STEP - 90.0)
            val sx = (cx + radius * cos(angle)).toFloat()
            val sy = (cy + radius * sin(angle)).toFloat()
            canvas.drawLine(cx, cy, sx, sy, axisPaint)

            val lRadius = radius + 44f
            val lx = (cx + lRadius * cos(angle)).toFloat()
            val ly = (cy + lRadius * sin(angle)).toFloat()
            canvas.drawText(axisLabels[i], lx, ly + 10f, labelPaint)
        }

        // Average layer (gray, under blue)
        if (hasAverage) {
            val avgPath = buildDataPath(cx, cy, radius, averageData)
            canvas.drawPath(avgPath, avgFillPaint)
            canvas.drawPath(avgPath, avgStrokePaint)
        }

        // Current layer (blue, on top)
        val curPath = buildDataPath(cx, cy, radius, currentData)
        canvas.drawPath(curPath, currentFillPaint)
        canvas.drawPath(curPath, currentStrokePaint)

        // Corner dots for current
        for (i in 0 until N_AXES) {
            val angle = Math.toRadians(i * ANGLE_STEP - 90.0)
            val px = (cx + radius * currentData[i] * cos(angle)).toFloat()
            val py = (cy + radius * currentData[i] * sin(angle)).toFloat()
            canvas.drawCircle(px, py, 6f, currentDotPaint)
        }

        // Legend
        drawLegend(canvas)
    }

    private fun buildDataPath(cx: Float, cy: Float, radius: Float, data: FloatArray): Path {
        val path = Path()
        for (i in 0 until N_AXES) {
            val angle = Math.toRadians(i * ANGLE_STEP - 90.0)
            val px = (cx + radius * data[i] * cos(angle)).toFloat()
            val py = (cy + radius * data[i] * sin(angle)).toFloat()
            if (i == 0) path.moveTo(px, py) else path.lineTo(px, py)
        }
        path.close()
        return path
    }

    private fun drawHexagon(canvas: Canvas, cx: Float, cy: Float, r: Float, paint: Paint) {
        val path = Path()
        for (i in 0 until N_AXES) {
            val angle = Math.toRadians(i * ANGLE_STEP - 90.0)
            val px = (cx + r * cos(angle)).toFloat()
            val py = (cy + r * sin(angle)).toFloat()
            if (i == 0) path.moveTo(px, py) else path.lineTo(px, py)
        }
        path.close()
        canvas.drawPath(path, paint)
    }

    private fun drawLegend(canvas: Canvas) {
        val lx = width - 16f
        val ly = 20f

        // Blue dot + "Today"
        canvas.drawCircle(lx - 70f, ly + 4f, 8f, currentDotPaint)
        val todayPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ContextCompat.getColor(context, R.color.blue); textSize = 30f; textAlign = Paint.Align.LEFT
        }
        canvas.drawText("Today", lx - 55f, ly + 12f, todayPaint)

        if (hasAverage) {
            val avgColor = ContextCompat.getColor(context, R.color.gray_50)
            canvas.drawCircle(lx - 70f, ly + 40f, 8f, Paint().apply { color = avgColor; style = Paint.Style.FILL })
            val avgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = avgColor; textSize = 30f; textAlign = Paint.Align.LEFT
            }
            canvas.drawText("30d avg", lx - 55f, ly + 48f, avgPaint)
        }
    }
}
