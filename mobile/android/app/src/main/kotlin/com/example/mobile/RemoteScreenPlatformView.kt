package com.example.mobile

import android.content.Context
import android.util.Log
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.platform.PlatformView

class RemoteScreenPlatformView(
    context: Context,
    private val bridge: RemoteScreenBridge,
    creationParams: Map<String, Any>?
) : PlatformView, SurfaceHolder.Callback {

    companion object {
        private const val TAG = "RemoteScreenPlatformView"
    }

    private val surfaceView: SurfaceView = SurfaceView(context)

    init {
        surfaceView.holder.addCallback(this)
        Log.d(TAG, "RemoteScreenPlatformView initialized")
    }

    override fun getView(): View {
        return surfaceView
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        Log.d(TAG, "Surface created: ${holder.surface}")
        RemoteScreenSession.getInstance().onSurfaceCreated(holder.surface)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        Log.d(TAG, "Surface changed: width=$width, height=$height")
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        Log.d(TAG, "Surface destroyed")
        RemoteScreenSession.getInstance().onSurfaceDestroyed()
    }

    override fun dispose() {
        Log.d(TAG, "Disposing RemoteScreenPlatformView")
        RemoteScreenSession.getInstance().onSurfaceDestroyed()
        surfaceView.holder.removeCallback(this)
    }
}
