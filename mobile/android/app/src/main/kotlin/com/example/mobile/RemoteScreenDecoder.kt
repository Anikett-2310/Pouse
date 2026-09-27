package com.example.mobile

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.nio.ByteBuffer
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

enum class DecoderState {
    UNINITIALIZED,
    WAITING_FOR_FIRST_IDR,
    DECODER_CONFIGURED,
    DECODING,
    DECODER_ERROR,
    DECODER_RESET,
}

data class RemoteScreenMetrics(
    val state: DecoderState,
    val wsReceivedFps: Double,
    val decoderOutputFps: Double,
    val framesReceived: Long,
    val framesDecoded: Long,
    val framesDropped: Long,
    val timeToFirstDecodedFrameMs: Long,
    val timeFromForcedIdrMs: Long,
    val lastAndroidReceiveTimeMs: Long,
    val lastCodecInputTimeMs: Long,
    val lastRenderedFrameTimeMs: Long,
    val isVideoWsConnected: Boolean,
    val stallLogged: Boolean,
    val uiState: String,
    val lastError: String?
)

class RemoteScreenDecoder(private val onMetricsUpdated: ((RemoteScreenMetrics) -> Unit)? = null) {

    companion object {
        private const val TAG = "PouseRemoteScreen"
        private const val DEFAULT_WIDTH = 1280
        private const val DEFAULT_HEIGHT = 720
    }

    private var webSocket: WebSocket? = null
    private var client: OkHttpClient? = null
    private var mediaCodec: MediaCodec? = null
    private var surface: Surface? = null

    @Volatile
    var state = DecoderState.UNINITIALIZED
        private set

    private var spsBytes: ByteArray? = null
    private var ppsBytes: ByteArray? = null

    private val framesReceived = AtomicLong(0)
    private val framesDecoded = AtomicLong(0)
    private val framesDropped = AtomicLong(0)

    private val keyframeReceivedCounter = AtomicLong(0)
    @Volatile private var currentKeyframeLogId = 0L
    @Volatile private var pendingRenderLogId = 0L

    private var connectStartTimeMs = 0L
    private var timeToFirstDecodedFrameMs = -1L
    private var forcedIdrRequestTimeMs = 0L
    private var timeFromForcedIdrMs = -1L
    private var lastErrorMessage: String? = null

    @Volatile private var lastAndroidReceiveTimeMs = 0L
    @Volatile private var lastCodecInputTimeMs = 0L
    @Volatile private var lastRenderedFrameTimeMs = 0L
    @Volatile private var isVideoWsConnected = false
    @Volatile private var stallLogged = false
    private var lastStallRecoveryTimeMs = 0L

    private var lastFpsCalcTimeMs = SystemClock.elapsedRealtime()
    private var lastWsCount = 0L
    private var lastDecodedCount = 0L
    private var currentWsFps = 0.0
    private var currentDecoderFps = 0.0

    private val mainHandler = Handler(Looper.getMainLooper())
    private val isDecodingActive = AtomicBoolean(false)

    private val stallCheckRunnable = object : Runnable {
        override fun run() {
            checkVideoStall()
            if (state == DecoderState.DECODING || state == DecoderState.WAITING_FOR_FIRST_IDR) {
                mainHandler.postDelayed(this, 500)
            }
        }
    }

    private fun checkVideoStall() {
        if (state != DecoderState.DECODING) return

        val now = SystemClock.elapsedRealtime()
        val surf = surface
        val surfaceValid = surf != null && surf.isValid

        if (lastRenderedFrameTimeMs == 0L) {
            lastRenderedFrameTimeMs = now
            return
        }

        val rxDelta = now - lastAndroidReceiveTimeMs
        val codecInDelta = now - lastCodecInputTimeMs
        val renderDelta = now - lastRenderedFrameTimeMs

        if (renderDelta > 1000) {
            if (!stallLogged) {
                stallLogged = true
                Log.w(
                    TAG,
                    "[DIAGNOSTIC] [VIDEO_STALL_DETECTED] lastRxMs=${rxDelta}ms lastCodecInMs=${codecInDelta}ms lastRenderMs=${renderDelta}ms decoderState=$state surfaceValid=$surfaceValid wsConnected=$isVideoWsConnected timestamp=${System.currentTimeMillis()}"
                )
            }

            if (now - lastStallRecoveryTimeMs < 3000) {
                return
            }
            lastStallRecoveryTimeMs = now

            if (!isVideoWsConnected) {
                Log.w(TAG, "[STALL RECOVERY] WebSocket disconnected. Triggering video loss recovery...")
                RemoteScreenSession.getInstance().handleVideoLoss()
            } else if (rxDelta > 1000) {
                Log.w(TAG, "[STALL RECOVERY] No WebSocket frames received for ${rxDelta}ms. Requesting single keyframe...")
                RemoteScreenSession.getInstance().requestKeyframe()
            } else if (!surfaceValid) {
                Log.w(TAG, "[STALL RECOVERY] Surface invalid or unmounted. Waiting for Surface...")
            } else {
                Log.w(TAG, "[STALL RECOVERY] MediaCodec output stalled (renderDelta=${renderDelta}ms). Resetting MediaCodec & requesting keyframe...")
                resetDecoder()
                RemoteScreenSession.getInstance().requestKeyframe()
            }
        }
    }

    fun setSurface(surf: Surface?) {
        val oldSurface = this.surface
        this.surface = surf
        Log.d(TAG, "[DECODER] Surface updated: $surf (old: $oldSurface)")

        if (surf != null && surf.isValid) {
            Log.d(TAG, "[DIAGNOSTIC] [SURFACE_VALID] surface=$surf timestamp=${System.currentTimeMillis()}")
            if (surf != oldSurface) {
                val codec = mediaCodec
                if (codec != null && (state == DecoderState.DECODING || state == DecoderState.DECODER_CONFIGURED)) {
                    try {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                            codec.setOutputSurface(surf)
                            Log.d(TAG, "[DECODER] MediaCodec output surface successfully updated via setOutputSurface")
                        } else {
                            reconfigureCodecWithSurface(surf)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "[DECODER] Exception calling setOutputSurface: ${e.message}. Reconfiguring MediaCodec...")
                        reconfigureCodecWithSurface(surf)
                    }
                } else if (state == DecoderState.WAITING_FOR_FIRST_IDR || state == DecoderState.UNINITIALIZED) {
                    if (spsBytes != null && ppsBytes != null) {
                        if (configureAndStartMediaCodec()) {
                            state = DecoderState.DECODING
                            Log.d(TAG, "[DECODER SUCCESS] Surface ready & MediaCodec configured with cached SPS/PPS! Requesting fresh IDR keyframe...")
                            RemoteScreenSession.getInstance().requestKeyframe()
                        }
                    } else {
                        RemoteScreenSession.getInstance().requestKeyframe()
                    }
                }
            }
        }
    }

    private fun reconfigureCodecWithSurface(newSurface: Surface) {
        try {
            mediaCodec?.stop()
            mediaCodec?.release()
        } catch (e: Exception) {
            Log.w(TAG, "[DECODER] Exception releasing old MediaCodec: ${e.message}")
        }
        mediaCodec = null
        if (spsBytes != null && ppsBytes != null) {
            if (configureAndStartMediaCodec()) {
                state = DecoderState.DECODING
                RemoteScreenSession.getInstance().requestKeyframe()
            }
        }
    }

    @Synchronized
    fun start(host: String, port: Int = 8081, sessionToken: String = "") {
        stop()

        state = DecoderState.WAITING_FOR_FIRST_IDR
        connectStartTimeMs = SystemClock.elapsedRealtime()
        timeToFirstDecodedFrameMs = -1L
        timeFromForcedIdrMs = -1L
        lastErrorMessage = null
        lastAndroidReceiveTimeMs = 0L
        lastCodecInputTimeMs = 0L
        lastRenderedFrameTimeMs = 0L
        stallLogged = false
        isVideoWsConnected = false
        framesReceived.set(0)
        framesDecoded.set(0)
        framesDropped.set(0)
        spsBytes = null
        ppsBytes = null
        currentKeyframeLogId = 0L
        pendingRenderLogId = 0L

        val redactedToken = RemoteScreenSession.redactToken(sessionToken)
        val wsUrl = if (sessionToken.isNotEmpty()) {
            "ws://$host:$port/screen?token=$sessionToken"
        } else {
            "ws://$host:$port/screen"
        }
        Log.d(TAG, "[DECODER] Connecting to Video WebSocket: ws://$host:$port/screen?token=$redactedToken")

        client = OkHttpClient.Builder()
            .connectTimeout(5, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .build()

        val request = Request.Builder()
            .url(wsUrl)
            .build()

        webSocket = client?.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                isVideoWsConnected = true
                Log.d(TAG, "[DIAGNOSTIC] VIDEO_WS_CONNECTED timestamp=${System.currentTimeMillis()} token=$redactedToken")
                Log.d(TAG, "[DIAGNOSTIC] [VIDEO_CONNECTED] timestamp=${System.currentTimeMillis()} token=$redactedToken")
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                processIncomingAccessUnit(bytes.toByteArray())
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                isVideoWsConnected = false
                Log.e(TAG, "[DIAGNOSTIC] [VIDEO_DISCONNECTED] failure=${t.message} timestamp=${System.currentTimeMillis()}")
                handleDecoderError("WebSocket connection failed: ${t.message}")
                RemoteScreenSession.getInstance().handleVideoLoss()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                isVideoWsConnected = false
                Log.d(TAG, "[DIAGNOSTIC] [VIDEO_DISCONNECTED] code=$code reason=$reason timestamp=${System.currentTimeMillis()}")
            }
        })

        mainHandler.removeCallbacks(stallCheckRunnable)
        mainHandler.postDelayed(stallCheckRunnable, 500)
    }

    fun stopVideoRendering() {
        Log.d(TAG, "[DECODER] Pausing video rendering (releasing MediaCodec)...")
        isDecodingActive.set(false)
        mainHandler.removeCallbacks(stallCheckRunnable)
        try {
            mediaCodec?.stop()
            mediaCodec?.release()
        } catch (e: Exception) {
            Log.e(TAG, "[DECODER] Error pausing MediaCodec: ${e.message}")
        }
        mediaCodec = null
    }

    private fun processIncomingAccessUnit(rawBytes: ByteArray) {
        if (rawBytes.isEmpty()) return
        val rxCount = framesReceived.incrementAndGet()
        lastAndroidReceiveTimeMs = SystemClock.elapsedRealtime()

        updateFpsMetricsIfNeeded()

        val nals = parseAnnexBNals(rawBytes)
        var containsIdr = false

        for (nal in nals) {
            if (nal.isEmpty()) continue
            val nalType: Int = nal[0].toInt() and 0x1F
            if (nalType == 7) { // SPS
                spsBytes = nal
            } else if (nalType == 8) { // PPS
                ppsBytes = nal
            } else if (nalType == 5) { // IDR
                containsIdr = true
                if (forcedIdrRequestTimeMs > 0 && timeFromForcedIdrMs < 0) {
                    timeFromForcedIdrMs = SystemClock.elapsedRealtime() - forcedIdrRequestTimeMs
                    Log.d(TAG, "[DECODER METRICS] Forced IDR recovery time: ${timeFromForcedIdrMs}ms")
                }
            }
        }

        val auTypeStr = if (containsIdr) "IDR" else if (spsBytes != null || ppsBytes != null) "SPS_PPS" else "P"

        if (containsIdr) {
            val idrId = keyframeReceivedCounter.incrementAndGet()
            currentKeyframeLogId = idrId
            pendingRenderLogId = idrId
            Log.d(TAG, "[DIAGNOSTIC] IDR_RECEIVED #$idrId (size=${rawBytes.size})")
            Log.d(
                TAG,
                "[DIAGNOSTIC] VIDEO_BINARY_RECEIVED size=${rawBytes.size} ANNEXB_AU_TYPE=$auTypeStr SPS_PRESENT=${spsBytes != null} PPS_PRESENT=${ppsBytes != null} CODEC_STATE=$state SURFACE_VALID=${surface?.isValid == true}"
            )
            if (spsBytes != null && ppsBytes != null) {
                Log.d(TAG, "[DIAGNOSTIC] SPS_PPS_READY (sps=${spsBytes?.size} pps=${ppsBytes?.size})")
            }
        }

        when (state) {
            DecoderState.WAITING_FOR_FIRST_IDR -> {
                if (containsIdr || (spsBytes != null && ppsBytes != null)) {
                    if (configureAndStartMediaCodec()) {
                        state = DecoderState.DECODING
                        timeToFirstDecodedFrameMs = SystemClock.elapsedRealtime() - connectStartTimeMs
                        Log.d(TAG, "[DECODER SUCCESS] First IDR decoded! Time to first frame: ${timeToFirstDecodedFrameMs}ms")
                        decodeAccessUnit(rawBytes)
                    } else {
                        Log.w(TAG, "[DECODER] Codec configuration deferred - surface not ready yet")
                    }
                } else {
                    Log.d(TAG, "[DECODER] Waiting for first IDR frame... (frame #$rxCount)")
                }
            }
            DecoderState.DECODING -> {
                decodeAccessUnit(rawBytes)
            }
            else -> {}
        }
    }

    @Synchronized
    private fun configureAndStartMediaCodec(): Boolean {
        val targetSurface = surface
        if (targetSurface == null || !targetSurface.isValid) {
            Log.e(TAG, "[DECODER ERROR] Cannot configure MediaCodec: Surface unavailable or invalid")
            return false
        }

        val sps = spsBytes
        val pps = ppsBytes

        if (sps == null || pps == null) {
            Log.e(TAG, "[DECODER ERROR] Missing SPS or PPS for MediaCodec configuration")
            return false
        }

        try {
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, DEFAULT_WIDTH, DEFAULT_HEIGHT)
            format.setByteBuffer("csd-0", ByteBuffer.wrap(sps))
            format.setByteBuffer("csd-1", ByteBuffer.wrap(pps))

            val codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            codec.configure(format, targetSurface, null, 0)
            codec.start()

            mediaCodec = codec
            state = DecoderState.DECODER_CONFIGURED
            isDecodingActive.set(true)
            Log.d(TAG, "[DIAGNOSTIC] CODEC_CONFIGURED (1280x720 AVC surfaceValid=${targetSurface.isValid})")
            Log.d(TAG, "[DECODER] MediaCodec configured & started successfully (1280x720 AVC)")
            return true
        } catch (e: Exception) {
            handleDecoderError("MediaCodec configuration failed: ${e.message}")
            return false
        }
    }

    private fun decodeAccessUnit(bytes: ByteArray) {
        val codec = mediaCodec ?: return
        val currentSurf = surface
        val renderToSurface = currentSurf != null && currentSurf.isValid

        val isIdrInThisAu = currentKeyframeLogId > 0 && currentKeyframeLogId == pendingRenderLogId
        val idrLogIdToUse = if (isIdrInThisAu) currentKeyframeLogId else 0L

        try {
            val inIndex = codec.dequeueInputBuffer(5_000)
            if (inIndex >= 0) {
                val inputBuffer = codec.getInputBuffer(inIndex)
                if (inputBuffer != null) {
                    inputBuffer.clear()
                    inputBuffer.put(bytes)
                    val ptsUs = SystemClock.elapsedRealtimeNanos() / 1000
                    codec.queueInputBuffer(inIndex, 0, bytes.size, ptsUs, 0)
                    lastCodecInputTimeMs = SystemClock.elapsedRealtime()
                    if (idrLogIdToUse > 0) {
                        Log.d(TAG, "[DIAGNOSTIC] IDR_QUEUED #$idrLogIdToUse")
                    }
                }
            } else {
                framesDropped.incrementAndGet()
                Log.w(TAG, "[DECODER LOW-LATENCY] Input buffer full - dropped stale frame to prevent latency backlog")
            }

            val info = MediaCodec.BufferInfo()
            var outIndex = codec.dequeueOutputBuffer(info, 5_000)
            while (outIndex >= 0) {
                codec.releaseOutputBuffer(outIndex, renderToSurface)
                if (renderToSurface) {
                    framesDecoded.incrementAndGet()
                    lastRenderedFrameTimeMs = SystemClock.elapsedRealtime()
                    stallLogged = false
                    if (pendingRenderLogId > 0) {
                        val renderedId = pendingRenderLogId
                        pendingRenderLogId = 0L
                        Log.d(TAG, "[DIAGNOSTIC] FRAME_RENDERED #$renderedId (outIndex=$outIndex timestamp=${System.currentTimeMillis()})")
                        Log.d(TAG, "[DIAGNOSTIC] OUTPUT_RENDERED frameCount=${framesDecoded.get()}")
                    }
                }
                outIndex = codec.dequeueOutputBuffer(info, 0)
            }
        } catch (e: Exception) {
            if (renderToSurface) {
                val errMsg = e.message ?: e.javaClass.simpleName
                Log.w(TAG, "[DIAGNOSTIC] [DECODER_RESET] Decode frame exception: $errMsg. Re-initializing decoder & requesting keyframe... timestamp=${System.currentTimeMillis()}")
                resetDecoder()
                RemoteScreenSession.getInstance().requestKeyframe()
            }
        }
    }

    fun requestForcedIdr() {
        forcedIdrRequestTimeMs = SystemClock.elapsedRealtime()
        timeFromForcedIdrMs = -1L
        Log.d(TAG, "[DECODER] Forced IDR requested at t=$forcedIdrRequestTimeMs")
    }

    @Synchronized
    fun resetDecoder() {
        Log.d(TAG, "[DIAGNOSTIC] [DECODER_RESET] timestamp=${System.currentTimeMillis()}")
        state = DecoderState.DECODER_RESET
        isDecodingActive.set(false)
        try {
            mediaCodec?.stop()
            mediaCodec?.release()
        } catch (e: Exception) {
            Log.e(TAG, "[DECODER] Exception releasing MediaCodec during reset: ${e.message}")
        }
        mediaCodec = null
        spsBytes = null
        ppsBytes = null
        currentKeyframeLogId = 0L
        pendingRenderLogId = 0L
        state = DecoderState.WAITING_FOR_FIRST_IDR
    }

    private fun handleDecoderError(msg: String) {
        Log.e(TAG, "[DECODER ERROR] $msg")
        lastErrorMessage = msg
        state = DecoderState.DECODER_ERROR
        isDecodingActive.set(false)
        emitMetrics()
    }

    private fun updateFpsMetricsIfNeeded() {
        val now = SystemClock.elapsedRealtime()
        val elapsed = now - lastFpsCalcTimeMs
        if (elapsed >= 1000) {
            val rx = framesReceived.get()
            val dec = framesDecoded.get()

            currentWsFps = ((rx - lastWsCount) * 1000.0) / elapsed
            currentDecoderFps = ((dec - lastDecodedCount) * 1000.0) / elapsed

            lastWsCount = rx
            lastDecodedCount = dec
            lastFpsCalcTimeMs = now

            emitMetrics()
        }
    }

    private fun computeUiState(): String {
        val sessionState = RemoteScreenSession.getInstance().state
        if (lastErrorMessage != null || state == DecoderState.DECODER_ERROR || sessionState == RemoteScreenState.ERROR) {
            return "ERROR"
        }
        if (sessionState == RemoteScreenState.RECONNECTING_VIDEO || sessionState == RemoteScreenState.RECONNECTING_CONTROL) {
            return "RECONNECTING"
        }
        if (stallLogged) {
            return "VIDEO_STALLED"
        }
        if (state == DecoderState.DECODING && framesDecoded.get() > 0) {
            return "LIVE"
        }
        if (state == DecoderState.DECODER_CONFIGURED || state == DecoderState.WAITING_FOR_FIRST_IDR) {
            return "WAITING_FOR_FIRST_FRAME"
        }
        if (isVideoWsConnected) {
            return "VIDEO_CONNECTED"
        }
        if (sessionState == RemoteScreenState.CONNECTING_CONTROL || sessionState == RemoteScreenState.AUTHENTICATED || sessionState == RemoteScreenState.STARTING_SCREEN) {
            return "CONNECTING"
        }
        return "CONNECTING"
    }

    private fun emitMetrics() {
        val metrics = RemoteScreenMetrics(
            state = state,
            wsReceivedFps = currentWsFps,
            decoderOutputFps = currentDecoderFps,
            framesReceived = framesReceived.get(),
            framesDecoded = framesDecoded.get(),
            framesDropped = framesDropped.get(),
            timeToFirstDecodedFrameMs = timeToFirstDecodedFrameMs,
            timeFromForcedIdrMs = timeFromForcedIdrMs,
            lastAndroidReceiveTimeMs = lastAndroidReceiveTimeMs,
            lastCodecInputTimeMs = lastCodecInputTimeMs,
            lastRenderedFrameTimeMs = lastRenderedFrameTimeMs,
            isVideoWsConnected = isVideoWsConnected,
            stallLogged = stallLogged,
            uiState = computeUiState(),
            lastError = lastErrorMessage
        )
        mainHandler.post {
            onMetricsUpdated?.invoke(metrics)
        }
    }

    private fun parseAnnexBNals(data: ByteArray): List<ByteArray> {
        val nals = ArrayList<ByteArray>()
        if (data.size < 4) return nals

        val len = data.size
        val startIndices = ArrayList<Pair<Int, Int>>()
        var i = 0

        while (i < len) {
            if (i + 3 < len && data[i] == 0.toByte() && data[i + 1] == 0.toByte() && data[i + 2] == 0.toByte() && data[i + 3] == 1.toByte()) {
                startIndices.add(Pair(i, 4))
                i += 4
            } else if (i + 2 < len && data[i] == 0.toByte() && data[i + 1] == 0.toByte() && data[i + 2] == 1.toByte()) {
                startIndices.add(Pair(i, 3))
                i += 3
            } else {
                i += 1
            }
        }

        for (idx in startIndices.indices) {
            let {
                val (start, prefixLen) = startIndices[idx]
                val nalStart = start + prefixLen
                val nalEnd = if (idx + 1 < startIndices.size) startIndices[idx + 1].first else len
                if (nalStart < nalEnd) {
                    val nal = ByteArray(nalEnd - nalStart)
                    System.arraycopy(data, nalStart, nal, 0, nalEnd - nalStart)
                    nals.add(nal)
                }
            }
        }
        return nals
    }

    @Synchronized
    fun stop() {
        Log.d(TAG, "[DECODER] Stopping RemoteScreenDecoder...")
        isDecodingActive.set(false)
        try {
            webSocket?.close(1000, "Stopping")
            webSocket = null
            client?.dispatcher?.executorService?.shutdown()
            client = null
        } catch (e: Exception) {
            Log.e(TAG, "[DECODER] Error closing websocket: ${e.message}")
        }

        try {
            mediaCodec?.stop()
            mediaCodec?.release()
        } catch (e: Exception) {
            Log.e(TAG, "[DECODER] Error releasing MediaCodec: ${e.message}")
        }
        mediaCodec = null
        state = DecoderState.UNINITIALIZED
        emitMetrics()
    }
}
