package com.pdcollect.app.ui.view

import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import kotlin.math.cos
import kotlin.math.sin

class SpiralCanvasView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private val templatePaint = Paint().apply {
        color = Color.LTGRAY
        style = Paint.Style.STROKE
        strokeWidth = 10f
        isAntiAlias = true
    }

    private val drawPaint = Paint().apply {
        color = Color.BLUE
        style = Paint.Style.STROKE
        strokeWidth = 8f
        isAntiAlias = true
        strokeCap = Paint.Cap.ROUND
    }

    private val path = Path()
    private val spiralPath = Path()

    /** Per-touch callback. Caller adds wall-clock + monotonic timing itself. */
    var onTouchData: ((x: Float, y: Float, action: String) -> Unit)? = null

    /**
     * Fired once, the first time the spiral template has actually been laid
     * out and drawn for the user to see. SpiralTracingActivity uses this to
     * mark the canonical "test presented" timestamp instead of guessing from
     * the user's first touch (which may arrive seconds later, or never).
     */
    var onCanvasReady: (() -> Unit)? = null
    private var notifiedReady = false

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        createSpiralPath(w, h)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawPath(spiralPath, templatePaint)
        canvas.drawPath(path, drawPaint)
        // Notify the activity *after* the first real draw, so the START
        // timestamp reflects when the user could actually see the template.
        // Posting to the View handler defers it past the current frame.
        if (!notifiedReady && spiralPath.let { !it.isEmpty }) {
            notifiedReady = true
            post { onCanvasReady?.invoke() }
        }
    }

    private fun createSpiralPath(w: Int, h: Int) {
        spiralPath.reset()
        val cx = w / 2f
        val cy = h / 2f
        val rMax = (if (w < h) w else h) / 2.2f
        
        // Archimedean spiral: r = a * theta
        val a = rMax / (4 * 2 * Math.PI.toFloat()) // 4 turns
        
        spiralPath.moveTo(cx, cy)
        for (theta in 0..1440) { // 4 turns * 360 degrees
            val rad = Math.toRadians(theta.toDouble()).toFloat()
            val r = a * rad
            val x = cx + r * cos(rad)
            val y = cy + r * sin(rad)
            spiralPath.lineTo(x, y)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        val x = event.x
        val y = event.y

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                path.moveTo(x, y)
                onTouchData?.invoke(x, y, "DOWN")
            }
            MotionEvent.ACTION_MOVE -> {
                path.lineTo(x, y)
                onTouchData?.invoke(x, y, "MOVE")
            }
            MotionEvent.ACTION_UP -> {
                onTouchData?.invoke(x, y, "UP")
            }
        }
        invalidate()
        return true
    }
    
    fun clear() {
        path.reset()
        invalidate()
    }
}
