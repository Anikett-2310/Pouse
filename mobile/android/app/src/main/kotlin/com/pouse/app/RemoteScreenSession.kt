package com.pouse.app

import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import org.json.JSONObject

enum class RemoteScreenState {
    IDLE,
    CONNECTING_CONTROL,
    AUTHENTICATED,
    STARTING_SCREEN,
    CONNECTED,
    RECONNECTING_VIDEO,
    RECONNECTING_CONTROL,
    STOPPED,
    EXPIRED,
    ERROR
}

class RemoteScreenSession private constructor() {

    companion object {
        private const val TAG = "RemoteScreenSession"

        @Volatile
        private var instance: RemoteScreenSession? = null

        fun getInstance(): RemoteScreenSession {
            return instance ?: synchronized(this) {
                instance ?: RemoteScreenSession().also { instance = it }
            }
        }

        fun redactToken(token: String?): String {
            if (token.isNullOrEmpty()) return "****"
            return if (token.length <= 8) "****" else token.substring(0, 4) + "...****"
        }
    }

    var state = RemoteScreenState.IDLE
        private set

    var pairToken: String? = null
    var screenSessionToken: String? = null
    var host: String = "127.0.0.1"
    var port: Int = 8081

    private var currentSurface: Surface? = null
    val decoder = RemoteScreenDecoder { metrics ->
        onMetricsUpdated?.invoke(metrics)
    }

    var onMetricsUpdated: ((RemoteScreenMetrics) -> Unit)? = null
    var sendControlMessage: ((String) -> Unit)? = null
    var onStateChanged: ((RemoteScreenState, String?) -> Unit)? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    fun updateState(newState: RemoteScreenState, message: String? = null) {
        Log.d(TAG, "[SESSION STATE] ${state.name} -> ${newState.name} (${message ?: ""})")
        state = newState
        mainHandler.post {
            onStateChanged?.invoke(newState, message)
        }
    }

    fun startSession(host: String, port: Int, pairToken: String) {
        if (state == RemoteScreenState.CONNECTED ||
            state == RemoteScreenState.STARTING_SCREEN ||
            state == RemoteScreenState.CONNECTING_CONTROL) {
            Log.d(TAG, "[SESSION] startSession called while already active in state ${state.name} - ignoring duplicate startSession")
            currentSurface?.let { decoder.setSurface(it) }
            return
        }

        this.host = host
        this.port = port
        this.pairToken = pairToken
        this.screenSessionToken = null
        this.videoReconnectAttempts = 0

        Log.d(TAG, "[DIAGNOSTIC] [SESSION_START] host=$host port=$port timestamp=${System.currentTimeMillis()}")
        updateState(RemoteScreenState.CONNECTING_CONTROL)

        // Send AUTH message over Control WS via Flutter callback
        val authMsg = JSONObject().apply {
            put("event", "AUTH")
            put("token", pairToken)
        }.toString()
        sendControlMessage?.invoke(authMsg)
    }

    fun handleControlMessage(jsonStr: String) {
        try {
            val json = JSONObject(jsonStr)
            val event = json.optString("event")

            when (event) {
                "AUTH_OK" -> {
                    Log.d(TAG, "[SESSION] AUTH_OK received from PC")
                    val previousState = state
                    updateState(RemoteScreenState.AUTHENTICATED)

                    // Only send START_SCREEN / RESUME_SCREEN if explicitly starting/reconnecting
                    if (previousState == RemoteScreenState.CONNECTING_CONTROL ||
                        previousState == RemoteScreenState.RECONNECTING_CONTROL) {
                        if (screenSessionToken != null) {
                            // Attempting RESUME_SCREEN
                            Log.d(TAG, "[SESSION] Sending RESUME_SCREEN with sessionToken=${redactToken(screenSessionToken)}")
                            val resumeMsg = JSONObject().apply {
                                put("event", "RESUME_SCREEN")
                                put("sessionToken", screenSessionToken)
                            }.toString()
                            sendControlMessage?.invoke(resumeMsg)
                        } else {
                            // Initial session creation: send START_SCREEN
                            Log.d(TAG, "[SESSION] Sending START_SCREEN")
                            updateState(RemoteScreenState.STARTING_SCREEN)
                            val startMsg = JSONObject().apply {
                                put("event", "START_SCREEN")
                                put("width", 1920)
                                put("height", 1080)
                            }.toString()
                            sendControlMessage?.invoke(startMsg)
                        }
                    } else {
                        Log.d(TAG, "[SESSION] AUTH_OK acknowledged in state $previousState - waiting for user to request Remote Screen")
                    }
                }
                "SCREEN_METADATA" -> {
                    val token = json.optString("screenSessionToken")
                    this.screenSessionToken = token
                    Log.d(TAG, "[SESSION] SCREEN_METADATA received. Session token: ${redactToken(token)}")

                    // Start Video WS stream: ws://host:port/screen?token=token
                    decoder.setSurface(currentSurface)
                    decoder.start(host, port, token)
                    updateState(RemoteScreenState.CONNECTED)
                }
                "RESUME_OK" -> {
                    val token = json.optString("screenSessionToken")
                    this.screenSessionToken = token
                    Log.d(TAG, "[SESSION] RESUME_OK received. Control re-associated with token=${redactToken(token)}")

                    // Re-request keyframe to recover stream
                    requestKeyframe()
                    updateState(RemoteScreenState.CONNECTED)
                }
                "STOP_SCREEN_OK" -> {
                    Log.d(TAG, "[SESSION] STOP_SCREEN_OK received")
                    teardownSession()
                    updateState(RemoteScreenState.STOPPED)
                }
                "INPUT_BLOCKED" -> {
                    val msg = json.optString("message", "Input blocked by active session owner")
                    Log.w(TAG, "[SESSION] INPUT_BLOCKED: $msg")
                }
                "SESSION_BUSY" -> {
                    val msg = json.optString("message", "Another session active")
                    Log.w(TAG, "[SESSION] SESSION_BUSY: $msg")
                    updateState(RemoteScreenState.ERROR, "Session busy: $msg")
                }
                "SESSION_EXPIRED" -> {
                    val msg = json.optString("message", "Session token expired")
                    Log.w(TAG, "[SESSION] SESSION_EXPIRED: $msg")
                    teardownSession()
                    updateState(RemoteScreenState.EXPIRED, msg)
                }
                "ERROR" -> {
                    val msg = json.optString("message", "Remote error")
                    Log.e(TAG, "[SESSION] ERROR received: $msg")
                    updateState(RemoteScreenState.ERROR, msg)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "[SESSION] Error processing control message: ${e.message}")
        }
    }

    fun requestKeyframe() {
        Log.d(TAG, "[DIAGNOSTIC] [KEYFRAME_REQUEST] timestamp=${System.currentTimeMillis()}")
        val msg = JSONObject().apply {
            put("event", "REQUEST_KEYFRAME")
        }.toString()
        sendControlMessage?.invoke(msg)
    }

    private var videoReconnectAttempts = 0
    private val MAX_VIDEO_RECONNECT_ATTEMPTS = 5

    fun resetReconnectAttempts() {
        videoReconnectAttempts = 0
    }

    fun handleVideoLoss() {
        if (state == RemoteScreenState.STOPPED || state == RemoteScreenState.IDLE || state == RemoteScreenState.ERROR) return

        if (videoReconnectAttempts >= MAX_VIDEO_RECONNECT_ATTEMPTS) {
            Log.e(TAG, "[SESSION] Max video reconnect attempts ($MAX_VIDEO_RECONNECT_ATTEMPTS) reached. Stopping reconnect loop.")
            updateState(RemoteScreenState.ERROR, "Video connection failed after $MAX_VIDEO_RECONNECT_ATTEMPTS attempts")
            return
        }

        videoReconnectAttempts++
        val delayMs = (1000L * (1 shl (videoReconnectAttempts - 1))).coerceAtMost(10000L)
        Log.w(TAG, "[DIAGNOSTIC] [VIDEO_RECONNECT_START] attempt=$videoReconnectAttempts delayMs=$delayMs timestamp=${System.currentTimeMillis()}")
        updateState(RemoteScreenState.RECONNECTING_VIDEO, "Reconnecting video ($videoReconnectAttempts/$MAX_VIDEO_RECONNECT_ATTEMPTS)...")

        mainHandler.postDelayed({
            if (state == RemoteScreenState.RECONNECTING_VIDEO) {
                decoder.resetDecoder()
                screenSessionToken?.let { token ->
                    decoder.start(host, port, token)
                    requestKeyframe()
                }
            }
        }, delayMs)
    }

    fun handleControlLoss() {
        if (state == RemoteScreenState.STOPPED || state == RemoteScreenState.IDLE) return
        Log.w(TAG, "[SESSION] Control WS connection lost. Entering RECONNECTING_CONTROL...")
        updateState(RemoteScreenState.RECONNECTING_CONTROL)
    }

    fun onSurfaceCreated(surface: Surface) {
        this.currentSurface = surface
        Log.d(TAG, "[DIAGNOSTIC] [SURFACE_CREATED] surface=$surface timestamp=${System.currentTimeMillis()}")
        decoder.setSurface(surface)

        if (state == RemoteScreenState.CONNECTED) {
            Log.d(TAG, "[SESSION] Surface recreated during active session - requesting keyframe")
            requestKeyframe()
        }
    }

    fun onSurfaceDestroyed() {
        Log.d(TAG, "[DIAGNOSTIC] [SURFACE_DESTROYED] timestamp=${System.currentTimeMillis()}")
        this.currentSurface = null
        decoder.setSurface(null)
    }

    fun onAppBackground() {
        Log.d(TAG, "[SESSION] App sent to background - pausing video rendering")
        if (state == RemoteScreenState.CONNECTED) {
            decoder.stopVideoRendering()
        }
    }

    fun onAppForeground() {
        Log.d(TAG, "[SESSION] App restored to foreground")
        if (state == RemoteScreenState.CONNECTED) {
            currentSurface?.let { surf ->
                decoder.setSurface(surf)
                requestKeyframe()
            }
        }
    }

    fun stopSession() {
        Log.d(TAG, "[DIAGNOSTIC] [SESSION_STOP] timestamp=${System.currentTimeMillis()}")
        val stopMsg = JSONObject().apply {
            put("event", "STOP_SCREEN")
        }.toString()
        sendControlMessage?.invoke(stopMsg)
        teardownSession()
        updateState(RemoteScreenState.STOPPED)
    }

    private fun teardownSession() {
        Log.d(TAG, "[SESSION] Performing complete native teardown")
        videoReconnectAttempts = 0
        decoder.stop()
        screenSessionToken = null
    }
}
