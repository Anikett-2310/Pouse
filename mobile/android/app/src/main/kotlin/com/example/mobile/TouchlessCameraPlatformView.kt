package com.example.mobile

import android.content.Context
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.camera.view.PreviewView
import io.flutter.plugin.platform.PlatformView

class ConstrainedFrameLayout(context: Context) : FrameLayout(context) {
    private var hasLogged = false

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val height = MeasureSpec.getSize(heightMeasureSpec)
        val exactWidthSpec = MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY)
        val exactHeightSpec = MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY)
        super.onMeasure(exactWidthSpec, exactHeightSpec)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        if (!hasLogged && width > 0 && height > 0) {
            hasLogged = true
            val previewW = if (childCount > 0) getChildAt(0).width else 0
            val previewH = if (childCount > 0) getChildAt(0).height else 0
            Log.e("POUSE_CAMERA", "PlatformView size: ${width}x${height}")
            Log.e("POUSE_CAMERA", "Native root size: ${width}x${height}")
            Log.e("POUSE_CAMERA", "PreviewView size: ${previewW}x${previewH}")
        }
    }
}

class TouchlessCameraPlatformView(
    private val context: Context,
    private val bridge: TouchlessCameraBridge,
    creationParams: Map<String, Any>?
) : PlatformView {

    companion object {
        private const val TAG = "TouchlessCamPlatformView"
    }

    private val containerView = ConstrainedFrameLayout(context).apply {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
    }

    private val previewView: PreviewView = PreviewView(context).apply {
        layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        scaleType = PreviewView.ScaleType.FILL_CENTER
    }

    private val skeletonOverlayView: HandSkeletonOverlayView = HandSkeletonOverlayView(context).apply {
        layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
    }

    init {
        Log.e("POUSE_CAMERA", "TouchlessCameraPlatformView constructor executed")
        Log.i(TAG, "TouchlessCameraPlatformView created with PreviewView & HandSkeletonOverlayView")
        containerView.addView(previewView)
        containerView.addView(skeletonOverlayView)
        bridge.attachPreviewSurfaceProvider(previewView.surfaceProvider)
        bridge.attachSkeletonOverlayView(skeletonOverlayView)
    }

    override fun getView(): View {
        return containerView
    }

    override fun dispose() {
        Log.i(TAG, "TouchlessCameraPlatformView disposed, detaching surface provider & skeleton overlay")
        bridge.detachSkeletonOverlayView()
        bridge.detachPreviewSurfaceProvider()
    }
}
