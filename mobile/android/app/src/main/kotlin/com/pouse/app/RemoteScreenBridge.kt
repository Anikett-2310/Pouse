package com.pouse.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class RemoteScreenBridge(
    private val context: Context,
    private val methodChannel: MethodChannel? = null
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val TAG = "RemoteScreenBridge"
        const val METHOD_CHANNEL_NAME = "pouse/remote_screen/method"
        const val EVENT_CHANNEL_NAME = "pouse/remote_screen/events"
    }

    private val session = RemoteScreenSession.getInstance()
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        session.onMetricsUpdated = { metrics ->
            sendMetricsEvent(metrics)
        }
        session.sendControlMessage = { jsonMsg ->
            mainHandler.post {
                methodChannel?.invokeMethod("sendControlMessage", mapOf("json" to jsonMsg))
            }
        }
        session.onStateChanged = { state, message ->
            mainHandler.post {
                methodChannel?.invokeMethod("onSessionStateChanged", mapOf(
                    "state" to state.name,
                    "message" to (message ?: "")
                ))
            }
        }
    }

    val decoder: RemoteScreenDecoder
        get() = session.decoder

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startSession" -> {
                val host = call.argument<String>("host") ?: "127.0.0.1"
                val port = call.argument<Int>("port") ?: 8081
                val pairToken = call.argument<String>("pairToken") ?: ""
                Log.d(TAG, "startSession called: host=$host, port=$port, pairToken=${RemoteScreenSession.redactToken(pairToken)}")
                session.startSession(host, port, pairToken)
                result.success(true)
            }
            "onControlMessage" -> {
                val json = call.argument<String>("json") ?: ""
                session.handleControlMessage(json)
                result.success(true)
            }
            "stopSession", "stop" -> {
                Log.d(TAG, "stopSession called via bridge")
                session.stopSession()
                result.success(true)
            }
            "requestForcedIdr" -> {
                Log.d(TAG, "requestForcedIdr called via bridge")
                session.requestKeyframe()
                result.success(true)
            }
            "resetDecoder" -> {
                Log.d(TAG, "resetDecoder called via bridge")
                session.decoder.resetDecoder()
                result.success(true)
            }
            "onAppBackground" -> {
                Log.d(TAG, "onAppBackground called via bridge")
                session.onAppBackground()
                result.success(true)
            }
            "onAppForeground" -> {
                Log.d(TAG, "onAppForeground called via bridge")
                session.onAppForeground()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        Log.d(TAG, "EventChannel listener attached")
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        Log.d(TAG, "EventChannel listener cancelled")
        this.eventSink = null
    }

    private fun sendMetricsEvent(metrics: RemoteScreenMetrics) {
        val map = mapOf(
            "sessionState" to session.state.name,
            "decoderState" to metrics.state.name,
            "state" to metrics.state.name,
            "wsReceivedFps" to metrics.wsReceivedFps,
            "decoderOutputFps" to metrics.decoderOutputFps,
            "framesReceived" to metrics.framesReceived,
            "framesDecoded" to metrics.framesDecoded,
            "framesDropped" to metrics.framesDropped,
            "timeToFirstDecodedFrameMs" to metrics.timeToFirstDecodedFrameMs,
            "timeFromForcedIdrMs" to metrics.timeFromForcedIdrMs,
            "lastAndroidReceiveTimeMs" to metrics.lastAndroidReceiveTimeMs,
            "lastCodecInputTimeMs" to metrics.lastCodecInputTimeMs,
            "lastRenderedFrameTimeMs" to metrics.lastRenderedFrameTimeMs,
            "isVideoWsConnected" to metrics.isVideoWsConnected,
            "stallLogged" to metrics.stallLogged,
            "uiState" to metrics.uiState,
            "lastError" to (metrics.lastError ?: "")
        )
        mainHandler.post {
            eventSink?.success(map)
        }
    }
}
