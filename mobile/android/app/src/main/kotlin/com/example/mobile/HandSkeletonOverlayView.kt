package com.example.mobile

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View

class HandSkeletonOverlayView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private var landmarks: List<Pair<Float, Float>> = emptyList()
    private var frameWidth: Int = 0
    private var frameHeight: Int = 0

    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF00E5FF.toInt()
        strokeWidth = 6f
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }

    private val jointPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFFFFFFF.toInt()
        style = Paint.Style.FILL
    }

    private val tipPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFFFC107.toInt()
        style = Paint.Style.FILL
    }

    private val tipHaloPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0x66FFC107.toInt()
        style = Paint.Style.FILL
    }

    companion object {
        private val CONNECTIONS = listOf(
            Pair(0, 1), Pair(1, 2), Pair(2, 3), Pair(3, 4),       // Thumb
            Pair(0, 5), Pair(5, 6), Pair(6, 7), Pair(7, 8),       // Index
            Pair(5, 9), Pair(9, 10), Pair(10, 11), Pair(11, 12),   // Middle
            Pair(9, 13), Pair(13, 14), Pair(14, 15), Pair(15, 16), // Ring
            Pair(13, 17), Pair(17, 18), Pair(18, 19), Pair(19, 20),// Pinky
            Pair(0, 17)                                            // Palm base
        )
    }

    fun updateLandmarks(points: List<Pair<Float, Float>>, imgW: Int, imgH: Int) {
        this.landmarks = points
        this.frameWidth = imgW
        this.frameHeight = imgH
        postInvalidate()
    }

    fun clearLandmarks() {
        if (landmarks.isNotEmpty()) {
            this.landmarks = emptyList()
            postInvalidate()
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val pts = landmarks
        if (pts.size < 21) return

        val viewW = width.toFloat()
        val viewH = height.toFloat()
        if (viewW <= 0f || viewH <= 0f) return

        val offsetX: Float
        val offsetY: Float
        val scaledWidth: Float
        val scaledHeight: Float

        if (frameWidth > 0 && frameHeight > 0) {
            val viewAspect = viewW / viewH
            val frameAspect = frameWidth.toFloat() / frameHeight.toFloat()

            if (viewAspect > frameAspect) {
                scaledWidth = viewW
                scaledHeight = viewW / frameAspect
                offsetX = 0f
                offsetY = (viewH - scaledHeight) / 2f
            } else {
                scaledHeight = viewH
                scaledWidth = viewH * frameAspect
                offsetX = (viewW - scaledWidth) / 2f
                offsetY = 0f
            }
        } else {
            scaledWidth = viewW
            scaledHeight = viewH
            offsetX = 0f
            offsetY = 0f
        }

        fun getPx(normX: Float): Float = offsetX + normX * scaledWidth
        fun getPy(normY: Float): Float = offsetY + normY * scaledHeight

        // Draw skeleton bones
        for (conn in CONNECTIONS) {
            val i1 = conn.first
            val i2 = conn.second
            if (i1 < pts.size && i2 < pts.size) {
                val p1 = pts[i1]
                val p2 = pts[i2]
                canvas.drawLine(
                    getPx(p1.first), getPy(p1.second),
                    getPx(p2.first), getPy(p2.second),
                    linePaint
                )
            }
        }

        // Draw joints
        for (i in pts.indices) {
            val p = pts[i]
            val x = getPx(p.first)
            val y = getPy(p.second)
            if (i == 8) { // Index fingertip (landmark 8)
                canvas.drawCircle(x, y, 22f, tipHaloPaint)
                canvas.drawCircle(x, y, 12f, tipPaint)
            } else {
                canvas.drawCircle(x, y, 7f, jointPaint)
            }
        }
    }
}
