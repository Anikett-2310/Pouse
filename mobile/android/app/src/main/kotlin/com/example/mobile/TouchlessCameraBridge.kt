package com.example.mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.sqrt

class TouchlessCameraBridge(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    init {
        Log.e("POUSE_TOUCHLESS", "TouchlessCameraBridge constructor executed")
    }

    companion object {
        const val METHOD_CHANNEL_NAME = "pouse/touchless_control"
        const val EVENT_CHANNEL_NAME = "pouse/touchless_events"
        private const val TAG = "TouchlessBridge"
    }

    private var eventSink: EventChannel.EventSink? = null
    private var handLandmarker: HandLandmarker? = null
    private var backgroundExecutor: ExecutorService? = null
    private var analysisExecutor: ExecutorService? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var previewSurfaceProvider: Preview.SurfaceProvider? = null
    private var skeletonOverlayView: HandSkeletonOverlayView? = null
    private var currentFrameWidth: Int = 0
    private var currentFrameHeight: Int = 0

    private val mainHandler = Handler(Looper.getMainLooper())

    private var isTracking = false
    private var isTrackingPaused = false
    private var sensitivity: Double = 1.0

    // Reference & Filter State
    private var lastIndexX: Double? = null
    private var lastIndexY: Double? = null
    private var filteredDx: Double = 0.0
    private var filteredDy: Double = 0.0

    // Diagnostics
    private var frameCounter: Long = 0
    private var lastLogTimeMs: Long = 0
    private var lastLandmarkBroadcastMs: Long = 0
    private var lastStatusEmitted: String = ""
    private var hasLoggedFirstFrame = false
    private var hasLoggedResultCallback = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startTracking" -> {
                Log.e("POUSE_TOUCHLESS", "startTracking method call received")
                Log.i(TAG, "[Diagnostic] startTracking MethodCall received")
                val sens = call.argument<Double>("sensitivity") ?: 1.0
                this.sensitivity = sens
                startTracking()
                result.success(true)
            }
            "stopTracking" -> {
                Log.i(TAG, "[Diagnostic] stopTracking MethodCall received")
                stopTracking()
                result.success(true)
            }
            "setSensitivity" -> {
                val sens = call.argument<Double>("sensitivity") ?: 1.0
                this.sensitivity = sens
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        Log.i(TAG, "[Diagnostic] EventChannel subscribed")
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        Log.i(TAG, "[Diagnostic] EventChannel cancelled")
        this.eventSink = null
    }

    fun attachPreviewSurfaceProvider(provider: Preview.SurfaceProvider) {
        this.previewSurfaceProvider = provider
        Log.i(TAG, "[Diagnostic] SurfaceProvider attached to TouchlessCameraBridge")
        if (isTracking) {
            bindCameraX()
        }
    }

    fun detachPreviewSurfaceProvider() {
        this.previewSurfaceProvider = null
        Log.i(TAG, "[Diagnostic] SurfaceProvider detached from TouchlessCameraBridge")
    }

    fun attachSkeletonOverlayView(overlayView: HandSkeletonOverlayView) {
        this.skeletonOverlayView = overlayView
        Log.i(TAG, "[Diagnostic] HandSkeletonOverlayView attached to TouchlessCameraBridge")
    }

    fun detachSkeletonOverlayView() {
        this.skeletonOverlayView = null
        Log.i(TAG, "[Diagnostic] HandSkeletonOverlayView detached from TouchlessCameraBridge")
    }

    private fun startTracking() {
        Log.e("POUSE_TOUCHLESS", "Touchless mode start: startTracking() called")
        if (isTracking) return
        isTracking = true
        lastIndexX = null
        lastIndexY = null
        filteredDx = 0.0
        filteredDy = 0.0
        frameCounter = 0
        lastLogTimeMs = 0
        lastStatusEmitted = ""
        hasLoggedFirstFrame = false
        hasLoggedResultCallback = false

        // Verify CAMERA permission natively
        val hasPermission = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        Log.e("POUSE_CAMERA", "CAMERA permission state: granted=$hasPermission")
        if (!hasPermission) {
            Log.e(TAG, "[Diagnostic] CAMERA permission is not granted natively")
            notifyStatus("PERMISSION_DENIED")
            return
        }

        notifyStatus("INITIALIZING")

        val modelPath = "hand_landmarker.task"
        var modelExists = false
        var modelSize: Long = -1
        var modelCanBeRead = false
        var modelHeaderHex = ""

        try {
            val afd = context.assets.openFd(modelPath)
            modelExists = true
            modelSize = afd.length
            afd.close()
        } catch (e: Exception) {
            try {
                context.assets.open(modelPath).use { stream ->
                    modelExists = true
                    modelSize = stream.available().toLong()
                }
            } catch (e2: Exception) {
                modelExists = false
                modelSize = 0
            }
        }

        if (modelExists) {
            try {
                context.assets.open(modelPath).use { stream ->
                    val buf = ByteArray(16)
                    val n = stream.read(buf)
                    modelCanBeRead = n > 0
                    modelHeaderHex = buf.take(n).joinToString(" ") { String.format("%02X", it) }
                }
            } catch (e: Exception) {
                modelCanBeRead = false
                modelHeaderHex = "READ_ERROR: ${e.javaClass.name}: ${e.message}"
            }
        }

        Log.e("POUSE_MEDIAPIPE", "HandLandmarker initialization start: modelPath=$modelPath, mode=LIVE_STREAM, modelExists=$modelExists, modelSize=$modelSize, readable=$modelCanBeRead")
        Log.i(TAG, "MEDIAPIPE MODEL:\npath=$modelPath\nexists=$modelExists\nsize=$modelSize\nreadable=$modelCanBeRead\nheader=$modelHeaderHex")
        Log.i(TAG, "[Diagnostic Stage 1] MediaPipe model load -> path=$modelPath, exists=$modelExists, size=$modelSize bytes, readable=$modelCanBeRead")

        backgroundExecutor = Executors.newSingleThreadExecutor()
        backgroundExecutor?.execute {
            var currentStage = "1. Model Asset Verification"
            try {
                if (!modelExists || !modelCanBeRead) {
                    throw IllegalStateException("Model asset '$modelPath' missing or unreadable (exists=$modelExists, size=$modelSize, readable=$modelCanBeRead)")
                }

                currentStage = "2. BaseOptions Creation"
                Log.i(TAG, "[Diagnostic Stage 2] Creating BaseOptions (Delegate.CPU)")
                Log.i(TAG, "[Diagnostic] Resolved MediaPipe version: 0.10.14")
                Log.i(TAG, "[Diagnostic] Running mode: RunningMode.LIVE_STREAM")

                var baseOptions: BaseOptions? = null
                var primaryException: Throwable? = null

                // Primary path: Asset path resolution
                try {
                    baseOptions = BaseOptions.builder()
                        .setModelAssetPath(modelPath)
                        .setDelegate(Delegate.CPU)
                        .build()
                } catch (e: Throwable) {
                    primaryException = e
                    Log.w(TAG, "[Diagnostic Stage 2] setModelAssetPath failed (${e.javaClass.name}: ${e.message}), trying in-memory ByteBuffer fallback...", e)
                }

                // Fallback path: Direct in-memory ByteBuffer (bypasses JNI AssetManager path lookups)
                if (baseOptions == null) {
                    try {
                        val modelBytes = context.assets.open(modelPath).use { it.readBytes() }
                        val directBuffer = java.nio.ByteBuffer.allocateDirect(modelBytes.size)
                        directBuffer.put(modelBytes)
                        directBuffer.flip()
                        baseOptions = BaseOptions.builder()
                            .setModelAssetBuffer(directBuffer)
                            .setDelegate(Delegate.CPU)
                            .build()
                        Log.i(TAG, "[Diagnostic Stage 2] BaseOptions created successfully via direct ByteBuffer fallback (${modelBytes.size} bytes)")
                    } catch (e: Throwable) {
                        Log.e(TAG, "[Diagnostic Stage 2] Both setModelAssetPath and setModelAssetBuffer failed", e)
                        throw primaryException ?: e
                    }
                }

                currentStage = "3. HandLandmarkerOptions Creation"
                Log.i(TAG, "[Diagnostic Stage 3] Creating HandLandmarkerOptions (LIVE_STREAM mode)")
                val options = HandLandmarker.HandLandmarkerOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setMinHandDetectionConfidence(0.5f)
                    .setMinTrackingConfidence(0.5f)
                    .setMinHandPresenceConfidence(0.5f)
                    .setNumHands(1)
                    .setRunningMode(RunningMode.LIVE_STREAM)
                    .setResultListener { result: HandLandmarkerResult, _: MPImage ->
                        handleLandmarkResult(result)
                    }
                    .setErrorListener { error: RuntimeException ->
                        val errClass = error.javaClass.name
                        val errMsg = error.message ?: "No message"
                        val errCause = error.cause?.let { "${it.javaClass.name}: ${it.message}" } ?: "None"
                        Log.e("POUSE_MEDIAPIPE", "MediaPipe error callback invoked: $errClass: $errMsg", error)
                        Log.e(TAG, "[Diagnostic Stage 5 Failure] MediaPipe Async Callback Error!\nClass: $errClass\nMessage: $errMsg\nCause: $errCause", error)
                        notifyError("MEDIAPIPE_ERROR [Stage 5: Async Callback Failure]\nException: $errClass\nMessage: $errMsg\nCause: $errCause", isMediaPipeError = true)
                    }
                    .build()

                currentStage = "4. HandLandmarker Creation (createFromOptions)"
                Log.e("POUSE_MEDIAPIPE", "HandLandmarker.createFromOptions starting...")
                Log.i(TAG, "[Diagnostic Stage 4] Invoking HandLandmarker.createFromOptions...")
                handLandmarker = HandLandmarker.createFromOptions(context, options)
                Log.e("POUSE_MEDIAPIPE", "HandLandmarker initialization SUCCESS")
                Log.i(TAG, "[Diagnostic Stage 4] HandLandmarker createFromOptions -> SUCCESS")

                currentStage = "5. LIVE_STREAM Start"
                Log.i(TAG, "[Diagnostic Stage 5] LIVE_STREAM start -> WORKING")
                notifyStatus("SEARCHING")

                mainHandler.post {
                    bindCameraX()
                }

            } catch (e: Throwable) {
                val exClass = e.javaClass.name
                val exMsg = e.message ?: "No message"
                val exCause = e.cause?.let { "${it.javaClass.name}: ${it.message}" } ?: "None"
                Log.e("POUSE_MEDIAPIPE", "HandLandmarker initialization FAILURE: $exClass: $exMsg", e)
                Log.e(TAG, "==================================================", e)
                Log.e(TAG, "[Diagnostic Failure] Stage: $currentStage", e)
                Log.e(TAG, "[Diagnostic Failure] Exception Class: $exClass")
                Log.e(TAG, "[Diagnostic Failure] Message: $exMsg")
                Log.e(TAG, "[Diagnostic Failure] Cause: $exCause")
                Log.e(TAG, "[Diagnostic Failure] Model: path=$modelPath, exists=$modelExists, size=$modelSize bytes")
                Log.e(TAG, "[Diagnostic Failure] MediaPipe resolved version: 0.10.14")
                Log.e(TAG, "[Diagnostic Failure] Delegate: CPU, RunningMode: LIVE_STREAM")
                Log.e(TAG, "==================================================", e)

                val fullDiagnostic = "MEDIAPIPE_ERROR [Failing Stage: $currentStage]\nException: $exClass\nMessage: $exMsg\nCause: $exCause\nModel: path=$modelPath, exists=$modelExists, size=$modelSize bytes, readable=$modelCanBeRead"
                notifyError(fullDiagnostic, isMediaPipeError = true)
            }
        }
    }

    // Diagnostic Pipeline Counters
    private var cameraFramesCount: Long = 0
    private var mpImageCount: Long = 0
    private var detectAsyncCount: Long = 0
    private var mediaPipeResultsCount: Long = 0
    private var handsDetectedCount: Long = 0
    private var landmarkProcessingCount: Long = 0
    private var lastTimestampMs: Long = 0

    private fun bindCameraX() {
        if (!isTracking) return

        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            Log.e("POUSE_CAMERA", "ProcessCameraProvider callback received")
            try {
                cameraProvider = cameraProviderFuture.get()
                cameraProvider?.unbindAll()

                val preview = Preview.Builder().build()
                if (previewSurfaceProvider != null) {
                    preview.setSurfaceProvider(previewSurfaceProvider)
                    Log.i(TAG, "[Diagnostic] CameraX preview -> WORKING")
                } else {
                    Log.i(TAG, "[Diagnostic] CameraX preview -> SurfaceProvider pending")
                }

                analysisExecutor = Executors.newSingleThreadExecutor()

                val imageAnalysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()

                imageAnalysis.setAnalyzer(analysisExecutor!!) { imageProxy ->
                    cameraFramesCount++
                    val rotationDegrees = imageProxy.imageInfo.rotationDegrees
                    val format = imageProxy.format
                    val width = imageProxy.width
                    val height = imageProxy.height

                    if (cameraFramesCount == 1L) {
                        Log.e("POUSE_CAMERA", "First ImageAnalysis frame received: width=${width}, height=${height}, format=$format, rotationDegrees=$rotationDegrees")
                    }

                    try {
                        val rawBitmap = imageProxy.toBitmap()
                        val matrix = android.graphics.Matrix()
                        if (rotationDegrees != 0) {
                            matrix.postRotate(rotationDegrees.toFloat())
                        }
                        // Front camera horizontal flip (mirroring) for intuitive tracking
                        matrix.postScale(-1f, 1f, rawBitmap.width / 2f, rawBitmap.height / 2f)

                        val rotatedBitmap = Bitmap.createBitmap(rawBitmap, 0, 0, rawBitmap.width, rawBitmap.height, matrix, true)
                        currentFrameWidth = rotatedBitmap.width
                        currentFrameHeight = rotatedBitmap.height

                        if (cameraFramesCount == 1L) {
                            Log.i(TAG, "[Diagnostic Image First Frame] format=$format, rotationDegrees=$rotationDegrees, rawSize=${width}x${height}, rotatedSize=${rotatedBitmap.width}x${rotatedBitmap.height}")
                        }

                        processFrame(rotatedBitmap)
                    } catch (e: Exception) {
                        Log.e(TAG, "[Diagnostic] Frame conversion error: ${e.javaClass.name}: ${e.message}", e)
                    } finally {
                        imageProxy.close()
                    }
                }
                Log.i(TAG, "[Diagnostic] CameraX ImageAnalysis -> WORKING")

                val cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA

                cameraProvider?.bindToLifecycle(
                    lifecycleOwner,
                    cameraSelector,
                    preview,
                    imageAnalysis
                )

                Log.e("POUSE_CAMERA", "CameraX bind SUCCESS")
                Log.i(TAG, "[Diagnostic] CameraX bound cleanly to single owner lifecycle")

            } catch (e: Exception) {
                Log.e("POUSE_CAMERA", "CameraX bind FAILURE: ${e.javaClass.name}: ${e.message}", e)
                Log.e(TAG, "[Diagnostic] CameraX bindToLifecycle exception: ${e.message}", e)
                notifyError("CAMERA_ERROR: ${e.javaClass.name}: ${e.message}")
            }
        }, ContextCompat.getMainExecutor(context))
    }

    enum class GestureState {
        SEARCHING,
        HAND_DETECTED,
        CLOSED_FIST,
        LEFT_PINCH_CANDIDATE,
        RIGHT_PINCH_CANDIDATE,
        PENDING_DOUBLE_CLICK,
        DRAGGING,
        TWO_FINGER_CANDIDATE,
        TWO_FINGER_SCROLLING,
        TWO_FINGER_BROWSER_NAV,
        THREE_FINGER_CANDIDATE,
        THREE_FINGER_COMMITTED,
        FOUR_FINGER_CANDIDATE,
        FOUR_FINGER_COMMITTED
    }

    private var gestureState: GestureState = GestureState.SEARCHING
    private var isLeftButtonHeld = false
    private var isRightButtonHeld = false

    private var pinchStartX: Float = 0f
    private var pinchStartY: Float = 0f
    private var multiFingerStartX: Float = 0f
    private var multiFingerStartY: Float = 0f
    private var lastScrollY: Float = 0f
    private var pendingDoubleReleaseTimeMs: Long = 0
    private var isSecondPinchInWindow = false

    private fun releaseButtons() {
        if (isLeftButtonHeld) {
            isLeftButtonHeld = false
            Log.i(TAG, "[Gesture Engine] Safely releasing held LEFT mouse button")
            sendEvent(mapOf("event" to "BUTTON_UP", "button" to "left"))
        }
        if (isRightButtonHeld) {
            isRightButtonHeld = false
            Log.i(TAG, "[Gesture Engine] Safely releasing held RIGHT mouse button")
            sendEvent(mapOf("event" to "BUTTON_UP", "button" to "right"))
        }
    }

    private fun stopTracking() {
        isTracking = false
        isTrackingPaused = false
        releaseButtons()
        gestureState = GestureState.SEARCHING
        lastIndexX = null
        lastIndexY = null
        hasLoggedFirstFrame = false
        hasLoggedResultCallback = false
        cameraFramesCount = 0
        mpImageCount = 0
        detectAsyncCount = 0
        mediaPipeResultsCount = 0
        handsDetectedCount = 0
        landmarkProcessingCount = 0
        lastTimestampMs = 0

        skeletonOverlayView?.clearLandmarks()

        try {
            cameraProvider?.unbindAll()
        } catch (e: Exception) {
            Log.w(TAG, "Error unbinding camera provider: ${e.message}")
        }
        cameraProvider = null

        try {
            handLandmarker?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Error closing HandLandmarker: ${e.message}")
        }
        handLandmarker = null

        backgroundExecutor?.shutdown()
        backgroundExecutor = null

        analysisExecutor?.shutdown()
        analysisExecutor = null

        notifyStatus("SEARCHING")
    }

    private fun processFrame(bitmap: Bitmap) {
        if (!isTracking || handLandmarker == null) return

        var timestampMs = System.currentTimeMillis()
        synchronized(this) {
            if (timestampMs <= lastTimestampMs) {
                timestampMs = lastTimestampMs + 1
            }
            lastTimestampMs = timestampMs
        }

        if (!hasLoggedFirstFrame) {
            hasLoggedFirstFrame = true
            Log.i(TAG, "[Diagnostic] MediaPipe frame received (First frame)")
        }

        try {
            val mpImage = BitmapImageBuilder(bitmap).build()
            mpImageCount++

            backgroundExecutor?.execute {
                try {
                    handLandmarker?.detectAsync(mpImage, timestampMs)
                    detectAsyncCount++
                    if (detectAsyncCount == 1L) {
                        Log.e("POUSE_MEDIAPIPE", "First detectAsync submission to MediaPipe")
                    }
                } catch (e: Exception) {
                    Log.e("POUSE_MEDIAPIPE", "detectAsync submission error: ${e.javaClass.name}: ${e.message}", e)
                    Log.e(TAG, "[Diagnostic] detectAsync submission error: ${e.javaClass.name}: ${e.message}", e)
                }
            }
        } catch (e: Exception) {
            Log.e("POUSE_MEDIAPIPE", "MPImage creation error: ${e.javaClass.name}: ${e.message}", e)
            Log.e(TAG, "[Diagnostic] MPImage creation error: ${e.javaClass.name}: ${e.message}", e)
        }

        val now = System.currentTimeMillis()
        if (now - lastLogTimeMs > 3000) {
            lastLogTimeMs = now
            val activeCase = when {
                cameraFramesCount == 0L -> "CASE A (Camera frames = 0, ImageAnalysis not running)"
                mpImageCount == 0L -> "CASE B (Camera frames > 0, MPImage = 0, image conversion failure)"
                detectAsyncCount > 0L && mediaPipeResultsCount == 0L -> "CASE C (MPImage > 0, detectAsync > 0, MediaPipe results = 0, callbacks waiting)"
                mediaPipeResultsCount > 0L && handsDetectedCount == 0L -> "CASE D (MediaPipe results > 0, 0 hands detected in frame - check orientation)"
                handsDetectedCount > 0L -> "CASE E (Hands detected > 0)"
                else -> "INITIALIZING"
            }

            val metricsStr = """
            [Diagnostic Pipeline Metrics]
            Camera frames: $cameraFramesCount
            MPImage frames: $mpImageCount
            detectAsync submitted: $detectAsyncCount
            MediaPipe results: $mediaPipeResultsCount
            hands detected: $handsDetectedCount
            landmark 8 processed: $landmarkProcessingCount
            Current Diagnosis: $activeCase
            """.trimIndent()

            Log.e("POUSE_TOUCHLESS", metricsStr)
            Log.i(TAG, metricsStr)
        }
    }

    fun notifyStatus(status: String) {
        if (lastStatusEmitted == status) return
        lastStatusEmitted = status
        Log.i(TAG, "[Diagnostic] Emitting status transition -> $status")
        sendEvent(mapOf("event" to "STATUS", "status" to status))
    }

    fun notifyError(message: String, isMediaPipeError: Boolean = false) {
        val status = if (isMediaPipeError) "MEDIAPIPE_ERROR" else "CAMERA_ERROR"
        Log.e(TAG, "[Diagnostic] Emitting error ($status) -> $message")
        sendEvent(mapOf("event" to "STATUS", "status" to status, "message" to message))
    }

    private fun checkIsClosedFist(
        landmarks: List<com.google.mediapipe.tasks.components.containers.NormalizedLandmark>
    ): Boolean {
        if (landmarks.size < 21) return false

        val wrist = landmarks[0]
        val indexMcp = landmarks[5]
        val indexTip = landmarks[8]

        val distWristIndexMcp = dist3D(wrist, indexMcp)
        val distWristIndexTip = dist3D(wrist, indexTip)
        val indexRatio = if (distWristIndexMcp > 0.0001f) distWristIndexTip / distWristIndexMcp else 2.0f

        // An extended Index finger (1-finger pointing ☝️) MUST NEVER be classified as CLOSED_FIST!
        if (indexRatio >= 1.25f) {
            return false
        }

        val fingerPairs = listOf(
            Pair(5, 8),   // Index: MCP 5, Tip 8
            Pair(9, 12),  // Middle: MCP 9, Tip 12
            Pair(13, 16), // Ring: MCP 13, Tip 16
            Pair(17, 20)  // Pinky: MCP 17, Tip 20
        )

        var curledCount = 0
        for ((mcpIdx, tipIdx) in fingerPairs) {
            val mcp = landmarks[mcpIdx]
            val tip = landmarks[tipIdx]

            val distWMcp = dist3D(wrist, mcp)
            val distWTip = dist3D(wrist, tip)

            val ratio = if (distWMcp > 0.0001f) distWTip / distWMcp else 2.0f
            if (ratio < 1.20f) {
                curledCount++
            }
        }

        return curledCount >= 3
    }

    private fun isFingerExtended(
        wrist: com.google.mediapipe.tasks.components.containers.NormalizedLandmark,
        mcp: com.google.mediapipe.tasks.components.containers.NormalizedLandmark,
        tip: com.google.mediapipe.tasks.components.containers.NormalizedLandmark
    ): Boolean {
        val distWristMcp = dist3D(wrist, mcp)
        val distWristTip = dist3D(wrist, tip)
        if (distWristMcp < 0.0001f) return false
        return (distWristTip / distWristMcp) > 1.30f
    }

    private fun dist3D(
        p1: com.google.mediapipe.tasks.components.containers.NormalizedLandmark,
        p2: com.google.mediapipe.tasks.components.containers.NormalizedLandmark
    ): Float {
        val dx = p1.x() - p2.x()
        val dy = p1.y() - p2.y()
        val dz = p1.z() - p2.z()
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    private fun handleLandmarkResult(result: HandLandmarkerResult) {
        mediaPipeResultsCount++
        if (mediaPipeResultsCount == 1L) {
            Log.e("POUSE_MEDIAPIPE", "First MediaPipe result callback received! handsDetected=${result.landmarks().size}")
        }
        if (!hasLoggedResultCallback) {
            hasLoggedResultCallback = true
            Log.i(TAG, "[Diagnostic] MediaPipe result callback executed (First callback)")
        }

        val landmarksList = result.landmarks()
        if (landmarksList.isEmpty() || landmarksList[0].isEmpty()) {
            skeletonOverlayView?.clearLandmarks()
            onHandLost()
            return
        }

        handsDetectedCount++
        val landmarks = landmarksList[0]
        val overlayPoints = landmarks.map { Pair(it.x(), it.y()) }
        skeletonOverlayView?.updateLandmarks(overlayPoints, currentFrameWidth, currentFrameHeight)

        if (landmarks.size < 21) return

        // 21 Landmarks detected = HAND PRESENT (Source of truth: NEVER show SEARCHING when 21 points exist)
        if (gestureState == GestureState.SEARCHING) {
            gestureState = GestureState.HAND_DETECTED
            notifyStatus("HAND_DETECTED")
        }

        val wrist = landmarks[0]
        val thumbTip = landmarks[4]
        val indexTip = landmarks[8]
        val middleTip = landmarks[12]
        val middleMcp = landmarks[9]

        val handScale = dist3D(wrist, middleMcp).let { if (it > 0.0001f) it else 0.25f }
        val distThumbIndex = dist3D(thumbTip, indexTip)
        val distThumbMiddle = dist3D(thumbTip, middleTip)

        val normThumbIndex = distThumbIndex / handScale
        val normThumbMiddle = distThumbMiddle / handScale

        val PINCH_ENTER = 0.25f
        val PINCH_EXIT = 0.45f

        val isLeftPinch = normThumbIndex < PINCH_ENTER
        val isLeftPinchRelease = normThumbIndex > PINCH_EXIT
        val isRightPinch = normThumbMiddle < PINCH_ENTER && normThumbIndex > 0.35f
        val isRightPinchRelease = normThumbMiddle > PINCH_EXIT

        val normIndexX = indexTip.x()
        val normIndexY = indexTip.y()
        val now = System.currentTimeMillis()

        // 1. Closed Fist Check (HIGHEST PRIORITY OVER ALL GESTURES/DRAG)
        val isFist = checkIsClosedFist(landmarks)
        if (isFist) {
            releaseButtons()
            isSecondPinchInWindow = false
            if (gestureState != GestureState.CLOSED_FIST) {
                gestureState = GestureState.CLOSED_FIST
                Log.i(TAG, "[Gesture Engine] Closed fist detected -> PAUSED_TRACKING")
                notifyStatus("PAUSED_TRACKING")
            }
            lastIndexX = null
            lastIndexY = null
            filteredDx = 0.0
            filteredDy = 0.0
            return
        }

        // Exiting Closed Fist
        if (gestureState == GestureState.CLOSED_FIST && !isFist) {
            gestureState = GestureState.HAND_DETECTED
            Log.i(TAG, "[Gesture Engine] Open hand detected -> HAND_DETECTED")
            notifyStatus("HAND_DETECTED")
            lastIndexX = null
            lastIndexY = null
            return
        }

        // 2. Double Click Expiry Check
        if (gestureState == GestureState.PENDING_DOUBLE_CLICK && now - pendingDoubleReleaseTimeMs > 250) {
            Log.i(TAG, "[Gesture Engine] 250ms double click window expired -> Emitting single LEFT_CLICK")
            sendEvent(mapOf("event" to "LEFT_CLICK"))
            notifyStatus("LEFT PINCH")
            gestureState = GestureState.HAND_DETECTED
            notifyStatus("HAND_DETECTED")
        }

        // Multi-Finger Extension Classification
        val indexExtended = isFingerExtended(wrist, landmarks[5], landmarks[8])
        val middleExtended = isFingerExtended(wrist, landmarks[9], landmarks[12])
        val ringExtended = isFingerExtended(wrist, landmarks[13], landmarks[16])
        val pinkyExtended = isFingerExtended(wrist, landmarks[17], landmarks[20])

        // 4-Finger Virtual Desktop Gestures (Index, Middle, Ring, Pinky extended)
        if (indexExtended && middleExtended && ringExtended && pinkyExtended) {
            if (gestureState != GestureState.FOUR_FINGER_CANDIDATE && gestureState != GestureState.FOUR_FINGER_COMMITTED) {
                gestureState = GestureState.FOUR_FINGER_CANDIDATE
                multiFingerStartX = normIndexX
                multiFingerStartY = normIndexY
            } else if (gestureState == GestureState.FOUR_FINGER_CANDIDATE) {
                val dx = normIndexX - multiFingerStartX
                val dy = normIndexY - multiFingerStartY
                val dist = sqrt(dx * dx + dy * dy)
                if (dist >= 0.025f) {
                    if (kotlin.math.abs(dx) > kotlin.math.abs(dy)) {
                        if (dx < 0f) {
                            sendEvent(mapOf("event" to "FOUR_FINGER_LEFT"))
                            notifyStatus("PREVIOUS VIRTUAL DESKTOP")
                        } else {
                            sendEvent(mapOf("event" to "FOUR_FINGER_RIGHT"))
                            notifyStatus("NEXT VIRTUAL DESKTOP")
                        }
                    }
                    // 4-finger UP/DOWN is explicitly UNUSED
                    gestureState = GestureState.FOUR_FINGER_COMMITTED
                }
            }
            return
        }

        // 3-Finger OS Gestures (Index, Middle, Ring extended)
        if (indexExtended && middleExtended && ringExtended && !pinkyExtended) {
            if (gestureState != GestureState.THREE_FINGER_CANDIDATE && gestureState != GestureState.THREE_FINGER_COMMITTED) {
                gestureState = GestureState.THREE_FINGER_CANDIDATE
                multiFingerStartX = normIndexX
                multiFingerStartY = normIndexY
            } else if (gestureState == GestureState.THREE_FINGER_CANDIDATE) {
                val dx = normIndexX - multiFingerStartX
                val dy = normIndexY - multiFingerStartY
                val dist = sqrt(dx * dx + dy * dy)
                if (dist >= 0.025f) {
                    if (kotlin.math.abs(dy) >= kotlin.math.abs(dx)) {
                        if (dy < 0f) {
                            sendEvent(mapOf("event" to "THREE_FINGER_UP"))
                            notifyStatus("TASK VIEW")
                        } else {
                            sendEvent(mapOf("event" to "THREE_FINGER_DOWN"))
                            notifyStatus("SHOW DESKTOP")
                        }
                    } else {
                        if (dx < 0f) {
                            sendEvent(mapOf("event" to "THREE_FINGER_LEFT"))
                            notifyStatus("PREVIOUS APP")
                        } else {
                            sendEvent(mapOf("event" to "THREE_FINGER_RIGHT"))
                            notifyStatus("NEXT APP")
                        }
                    }
                    gestureState = GestureState.THREE_FINGER_COMMITTED
                }
            }
            return
        }

        // 2-Finger Gestures (Scroll OR Browser Navigation)
        if (indexExtended && middleExtended && !ringExtended && !pinkyExtended) {
            if (gestureState != GestureState.TWO_FINGER_CANDIDATE &&
                gestureState != GestureState.TWO_FINGER_SCROLLING &&
                gestureState != GestureState.TWO_FINGER_BROWSER_NAV) {
                gestureState = GestureState.TWO_FINGER_CANDIDATE
                multiFingerStartX = normIndexX
                multiFingerStartY = normIndexY
                lastScrollY = normIndexY
            } else if (gestureState == GestureState.TWO_FINGER_CANDIDATE) {
                val dx = normIndexX - multiFingerStartX
                val dy = normIndexY - multiFingerStartY
                val dist = sqrt(dx * dx + dy * dy)
                if (dist >= 0.020f) {
                    if (kotlin.math.abs(dy) >= kotlin.math.abs(dx)) {
                        gestureState = GestureState.TWO_FINGER_SCROLLING
                        lastScrollY = normIndexY
                        notifyStatus("SCROLLING")
                    } else {
                        gestureState = GestureState.TWO_FINGER_BROWSER_NAV
                        notifyStatus("BROWSER NAVIGATION")
                        if (dx < 0f) {
                            sendEvent(mapOf("event" to "BROWSER_FORWARD"))
                        } else {
                            sendEvent(mapOf("event" to "BROWSER_BACK"))
                        }
                    }
                }
            } else if (gestureState == GestureState.TWO_FINGER_SCROLLING) {
                val rawDy = normIndexY - lastScrollY
                lastScrollY = normIndexY
                if (kotlin.math.abs(rawDy) > 0.003f) {
                    val scrollDy = rawDy * 1000.0
                    sendEvent(mapOf("event" to "SCROLL", "dx" to 0.0, "dy" to scrollDy))
                    notifyStatus("SCROLLING")
                }
            }
            return
        }

        // Reset multi-finger states if returning to single finger / pinch gesture
        if (gestureState == GestureState.TWO_FINGER_CANDIDATE ||
            gestureState == GestureState.TWO_FINGER_SCROLLING ||
            gestureState == GestureState.TWO_FINGER_BROWSER_NAV ||
            gestureState == GestureState.THREE_FINGER_CANDIDATE ||
            gestureState == GestureState.THREE_FINGER_COMMITTED ||
            gestureState == GestureState.FOUR_FINGER_CANDIDATE ||
            gestureState == GestureState.FOUR_FINGER_COMMITTED) {
            gestureState = GestureState.HAND_DETECTED
            lastIndexX = null
            lastIndexY = null
        }

        // 3. Gesture State Machine (Single Finger / Pinch / Drag)
        when (gestureState) {
            GestureState.CLOSED_FIST -> {
                // Handled above
            }
            GestureState.PENDING_DOUBLE_CLICK -> {
                if (isLeftPinch) {
                    isSecondPinchInWindow = true
                    pinchStartX = normIndexX
                    pinchStartY = normIndexY
                    gestureState = GestureState.LEFT_PINCH_CANDIDATE
                    notifyStatus("LEFT PINCH")
                    lastIndexX = normIndexX.toDouble()
                    lastIndexY = normIndexY.toDouble()
                } else {
                    onHandMovement(normIndexX.toDouble(), normIndexY.toDouble())
                }
            }
            GestureState.HAND_DETECTED -> {
                notifyStatus("HAND_DETECTED")
                if (isLeftPinch) {
                    isSecondPinchInWindow = false
                    pinchStartX = normIndexX
                    pinchStartY = normIndexY
                    gestureState = GestureState.LEFT_PINCH_CANDIDATE
                    notifyStatus("LEFT PINCH")
                    lastIndexX = normIndexX.toDouble()
                    lastIndexY = normIndexY.toDouble()
                } else if (isRightPinch) {
                    gestureState = GestureState.RIGHT_PINCH_CANDIDATE
                    notifyStatus("RIGHT PINCH")
                    lastIndexX = normIndexX.toDouble()
                    lastIndexY = normIndexY.toDouble()
                } else {
                    onHandMovement(normIndexX.toDouble(), normIndexY.toDouble())
                }
            }
            GestureState.LEFT_PINCH_CANDIDATE -> {
                // LOCK POINTER MOVEMENT during pinch acquisition:
                // Continuously update tracking baseline so pinch-closing index motion is swallowed.
                lastIndexX = normIndexX.toDouble()
                lastIndexY = normIndexY.toDouble()

                val dx = normIndexX - pinchStartX
                val dy = normIndexY - pinchStartY
                val moveDist = sqrt(dx * dx + dy * dy)

                if (moveDist >= 0.015f) {
                    gestureState = GestureState.DRAGGING
                    isLeftButtonHeld = true
                    Log.i(TAG, "[Gesture Engine] Drag threshold (0.015) exceeded -> BUTTON_DOWN(left) & DRAGGING")
                    sendEvent(mapOf("event" to "BUTTON_DOWN", "button" to "left"))
                    notifyStatus("DRAGGING")
                    // Re-establish fresh baseline at current drag activation point (no cursor jump)
                    lastIndexX = normIndexX.toDouble()
                    lastIndexY = normIndexY.toDouble()
                } else if (isLeftPinchRelease) {
                    if (isSecondPinchInWindow) {
                        Log.i(TAG, "[Gesture Engine] Second pinch released within 250ms -> Emitting DOUBLE_CLICK")
                        sendEvent(mapOf("event" to "DOUBLE_CLICK"))
                        notifyStatus("DOUBLE CLICK")
                        isSecondPinchInWindow = false
                        gestureState = GestureState.HAND_DETECTED
                        lastIndexX = null
                        lastIndexY = null
                    } else {
                        gestureState = GestureState.PENDING_DOUBLE_CLICK
                        pendingDoubleReleaseTimeMs = System.currentTimeMillis()
                        mainHandler.postDelayed({
                            if (gestureState == GestureState.PENDING_DOUBLE_CLICK && System.currentTimeMillis() - pendingDoubleReleaseTimeMs >= 250) {
                                Log.i(TAG, "[Gesture Engine] Delayed timer expired -> Emitting single LEFT_CLICK")
                                sendEvent(mapOf("event" to "LEFT_CLICK"))
                                notifyStatus("LEFT PINCH")
                                gestureState = GestureState.HAND_DETECTED
                                notifyStatus("HAND_DETECTED")
                            }
                        }, 260)
                        lastIndexX = null
                        lastIndexY = null
                    }
                }
            }
            GestureState.RIGHT_PINCH_CANDIDATE -> {
                // LOCK POINTER MOVEMENT during right pinch acquisition:
                lastIndexX = normIndexX.toDouble()
                lastIndexY = normIndexY.toDouble()

                if (isRightPinchRelease) {
                    Log.i(TAG, "[Gesture Engine] Right pinch released -> Emitting RIGHT_CLICK")
                    sendEvent(mapOf("event" to "RIGHT_CLICK"))
                    notifyStatus("RIGHT PINCH")
                    gestureState = GestureState.HAND_DETECTED
                    lastIndexX = null
                    lastIndexY = null
                }
            }
            GestureState.DRAGGING -> {
                notifyStatus("DRAGGING")
                if (isLeftPinchRelease) {
                    Log.i(TAG, "[Gesture Engine] Drag released -> BUTTON_UP(left)")
                    releaseButtons()
                    gestureState = GestureState.HAND_DETECTED
                    notifyStatus("HAND_DETECTED")
                    lastIndexX = null
                    lastIndexY = null
                } else {
                    onHandMovement(normIndexX.toDouble(), normIndexY.toDouble())
                }
            }
            else -> {
                gestureState = GestureState.HAND_DETECTED
            }
        }

        // Throttle Flutter EventChannel landmark broadcast (10fps / 100ms) to eliminate IPC overhead
        if (now - lastLandmarkBroadcastMs > 100) {
            lastLandmarkBroadcastMs = now
            val points = landmarks.map { mapOf("x" to it.x().toDouble(), "y" to it.y().toDouble()) }
            sendEvent(mapOf("event" to "LANDMARKS", "landmarks" to points))
        }
    }

    private fun onHandMovement(normX: Double, normY: Double) {
        val lastX = lastIndexX
        val lastY = lastIndexY

        if (lastX == null || lastY == null) {
            lastIndexX = normX
            lastIndexY = normY
            return
        }

        val rawDx = normX - lastX
        val rawDy = normY - lastY

        lastIndexX = normX
        lastIndexY = normY

        val distance = sqrt(rawDx * rawDx + rawDy * rawDy)
        // Dead zone: ignore tiny movements < 0.002 normalized units
        if (distance < 0.002) return

        // Adaptive EMA filter:
        // Fast motion (distance >= 0.005): alpha = 0.85 (85% raw motion = ultra-low lag).
        // Micro-motion (distance < 0.005): alpha = 0.50 (50% raw motion = jitter-free holding).
        val alpha = if (distance >= 0.005) 0.85 else 0.50
        filteredDx = alpha * rawDx + (1.0 - alpha) * filteredDx
        filteredDy = alpha * rawDy + (1.0 - alpha) * filteredDy

        // Convert normalized delta to logical pixel movement
        val dx = filteredDx * 1200.0 * sensitivity
        val dy = filteredDy * 1200.0 * sensitivity

        if (absVal(dx) >= 0.1 || absVal(dy) >= 0.1) {
            sendEvent(mapOf("event" to "MOVE", "dx" to dx, "dy" to dy, "ts" to System.currentTimeMillis()))
        }
    }

    private fun onHandLost() {
        if (lastIndexX != null || lastIndexY != null) {
            Log.i(TAG, "[Diagnostic] Hand lost by MediaPipe")
        }
        skeletonOverlayView?.clearLandmarks()
        releaseButtons()
        isTrackingPaused = false
        gestureState = GestureState.SEARCHING
        lastIndexX = null
        lastIndexY = null
        filteredDx = 0.0
        filteredDy = 0.0
        notifyStatus("SEARCHING")
        sendEvent(mapOf("event" to "STATUS", "status" to "HAND_LOST"))
        sendEvent(mapOf("event" to "LANDMARKS", "landmarks" to emptyList<Map<String, Double>>()))
    }

    private fun sendEvent(eventData: Map<String, Any>) {
        mainHandler.post {
            eventSink?.success(eventData)
        }
    }

    private fun absVal(v: Double): Double = if (v < 0) -v else v
}
