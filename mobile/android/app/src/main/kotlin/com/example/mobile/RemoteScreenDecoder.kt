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

    private var connectStartTimeMs = 0L
    private var timeToFirstDecodedFrameMs = -1L
    private var forcedIdrRequestTimeMs = 0L
    private var timeFromForcedIdrMs = -1L
    private var lastErrorMessage: String? = null

    private var lastFpsCalcTimeMs = SystemClock.elapsedRealtime()
    private var lastWsCount = 0L
    private var lastDecodedCount = 0L
    private var currentWsFps = 0.0
    private var currentDecoderFps = 0.0

    private val mainHandler = Handler(Looper.getMainLooper())
    private val isDecodingActive = AtomicBoolean(false)

    fun setSurface(surf: Surface?) {
        this.surface = surf
        Log.d(TAG, "[DECODER] Surface updated: $surf")
    }

    @Synchronized
    fun start(host: String, port: Int = 8081, sessionToken: String = "") {
        stop()

        state = DecoderState.WAITING_FOR_FIRST_IDR
        connectStartTimeMs = SystemClock.elapsedRealtime()
        timeToFirstDecodedFrameMs = -1L
        timeFromForcedIdrMs = -1L
        lastErrorMessage = null
        framesReceived.set(0)
        framesDecoded.set(0)
        framesDropped.set(0)
        spsBytes = null
        ppsBytes = null

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
                Log.d(TAG, "[DECODER WEBSOCKET] Connected to Video WS with token=$redactedToken")
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                processIncomingAccessUnit(bytes.toByteArray())
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "[DECODER WEBSOCKET] Connection failure: ${t.message}")
                handleDecoderError("WebSocket connection failed: ${t.message}")
                RemoteScreenSession.getInstance().handleVideoLoss()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.d(TAG, "[DECODER WEBSOCKET] Closed: $code / $reason")
            }
        })
    }

    fun stopVideoRendering() {
        Log.d(TAG, "[DECODER] Pausing video rendering (releasing MediaCodec)...")
        isDecodingActive.set(false)
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

        when (state) {
            DecoderState.WAITING_FOR_FIRST_IDR -> {
                if (containsIdr || (spsBytes != null && ppsBytes != null)) {
                    if (configureAndStartMediaCodec()) {
                        state = DecoderState.DECODING
                        timeToFirstDecodedFrameMs = SystemClock.elapsedRealtime() - connectStartTimeMs
                        Log.d(TAG, "[DECODER SUCCESS] First IDR decoded! Time to first frame: ${timeToFirstDecodedFrameMs}ms")
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
            Log.d(TAG, "[DECODER] MediaCodec configured & started successfully (1280x720 AVC)")
            return true
        } catch (e: Exception) {
            handleDecoderError("MediaCodec configuration failed: ${e.message}")
            return false
        }
    }

    private fun decodeAccessUnit(bytes: ByteArray) {
        val codec = mediaCodec ?: return
        try {
            val inIndex = codec.dequeueInputBuffer(5_000)
            if (inIndex >= 0) {
                val inputBuffer = codec.getInputBuffer(inIndex)
                if (inputBuffer != null) {
                    inputBuffer.clear()
                    inputBuffer.put(bytes)
                    val ptsUs = SystemClock.elapsedRealtimeNanos() / 1000
                    codec.queueInputBuffer(inIndex, 0, bytes.size, ptsUs, 0)
                }
            } else {
                // Queue full - drop frame to maintain low-latency
                framesDropped.incrementAndGet()
                Log.w(TAG, "[DECODER LOW-LATENCY] Input buffer full - dropped stale frame to prevent latency backlog")
            }

            // Drain output buffer to Surface
            val info = MediaCodec.BufferInfo()
            var outIndex = codec.dequeueOutputBuffer(info, 5_000)
            while (outIndex >= 0) {
                codec.releaseOutputBuffer(outIndex, true)
                framesDecoded.incrementAndGet()
                outIndex = codec.dequeueOutputBuffer(info, 0)
            }
        } catch (e: Exception) {
            handleDecoderError("Decode frame exception: ${e.message}")
        }
    }

    fun requestForcedIdr() {
        forcedIdrRequestTimeMs = SystemClock.elapsedRealtime()
        timeFromForcedIdrMs = -1L
        Log.d(TAG, "[DECODER] Forced IDR requested at t=$forcedIdrRequestTimeMs")
    }

    @Synchronized
    fun resetDecoder() {
        Log.d(TAG, "[DECODER] Performing explicit decoder reset/restart test...")
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
