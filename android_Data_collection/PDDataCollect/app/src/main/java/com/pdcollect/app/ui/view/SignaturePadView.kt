package com.pdcollect.app.ui.view

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.os.Parcel
import android.os.Parcelable
import android.util.AttributeSet
import android.util.Base64
import android.view.MotionEvent
import android.view.View
import androidx.core.content.ContextCompat
import com.pdcollect.app.R

class SignaturePadView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : View(context, attrs, defStyleAttr) {

    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ContextCompat.getColor(context, R.color.onboarding_accent)
        style = Paint.Style.STROKE
        strokeWidth = dp(2.5f)
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private val strokes = mutableListOf<MutableList<Pair<Float, Float>>>()
    private var activeStroke: MutableList<Pair<Float, Float>>? = null
    private val drawPaths = mutableListOf<Path>()
    var onSignatureChanged: (() -> Unit)? = null

    init {
        setBackgroundResource(R.drawable.bg_onboarding_signature_border)
    }

    fun isEmpty(): Boolean = strokes.isEmpty() && activeStroke == null

    fun clear() {
        strokes.clear()
        activeStroke = null
        drawPaths.clear()
        invalidate()
        onSignatureChanged?.invoke()
    }

    fun exportPngBase64(): String? {
        if (isEmpty() || width <= 0 || height <= 0) return null
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(0x00000000)
        for (path in buildDrawPaths()) {
            canvas.drawPath(path, strokePaint)
        }
        val bytes = java.io.ByteArrayOutputStream()
        if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes)) return null
        return Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                parent.requestDisallowInterceptTouchEvent(true)
                activeStroke = mutableListOf(event.x to event.y)
                invalidate()
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                activeStroke?.add(event.x to event.y)
                invalidate()
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                activeStroke?.let { stroke ->
                    if (stroke.size >= 2) {
                        strokes.add(stroke)
                    }
                }
                activeStroke = null
                rebuildDrawPaths()
                invalidate()
                onSignatureChanged?.invoke()
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        for (path in buildDrawPaths()) {
            canvas.drawPath(path, strokePaint)
        }
    }

    private fun buildDrawPaths(): List<Path> {
        if (activeStroke != null) {
            rebuildDrawPaths()
        }
        return drawPaths
    }

    private fun rebuildDrawPaths() {
        drawPaths.clear()
        for (stroke in strokes) {
            drawPaths.add(stroke.toPath())
        }
        activeStroke?.let { drawPaths.add(it.toPath()) }
    }

    private fun List<Pair<Float, Float>>.toPath(): Path {
        val path = Path()
        if (isEmpty()) return path
        path.moveTo(this[0].first, this[0].second)
        for (index in 1 until size) {
            path.lineTo(this[index].first, this[index].second)
        }
        return path
    }

    private fun dp(value: Float): Float = value * resources.displayMetrics.density

    override fun onSaveInstanceState(): Parcelable {
        val superState = super.onSaveInstanceState()
        return SavedState(superState).apply {
            serializedStrokes = strokes.map { stroke ->
                stroke.flatMap { listOf(it.first, it.second) }.toFloatArray()
            }.toTypedArray()
        }
    }

    override fun onRestoreInstanceState(state: Parcelable?) {
        if (state !is SavedState) {
            super.onRestoreInstanceState(state)
            return
        }
        super.onRestoreInstanceState(state.superState)
        strokes.clear()
        state.serializedStrokes?.forEach { flat ->
            val stroke = mutableListOf<Pair<Float, Float>>()
            var index = 0
            while (index + 1 < flat.size) {
                stroke.add(flat[index] to flat[index + 1])
                index += 2
            }
            if (stroke.size >= 2) {
                strokes.add(stroke)
            }
        }
        rebuildDrawPaths()
        invalidate()
    }

    private class SavedState : BaseSavedState {
        var serializedStrokes: Array<FloatArray>? = null

        constructor(superState: Parcelable?) : super(superState)

        constructor(source: Parcel) : super(source) {
            val count = source.readInt()
            serializedStrokes = if (count >= 0) {
                Array(count) { index ->
                    source.createFloatArray() ?: FloatArray(0)
                }
            } else {
                null
            }
        }

        override fun writeToParcel(out: Parcel, flags: Int) {
            super.writeToParcel(out, flags)
            val data = serializedStrokes
            if (data == null) {
                out.writeInt(-1)
            } else {
                out.writeInt(data.size)
                data.forEach { out.writeFloatArray(it) }
            }
        }

        companion object {
            @JvmField
            val CREATOR = object : Parcelable.Creator<SavedState> {
                override fun createFromParcel(source: Parcel) = SavedState(source)
                override fun newArray(size: Int) = arrayOfNulls<SavedState>(size)
            }
        }
    }
}
