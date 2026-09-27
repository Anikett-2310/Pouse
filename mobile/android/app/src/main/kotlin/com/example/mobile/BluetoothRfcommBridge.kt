package com.example.mobile

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStream
import java.util.UUID
import kotlin.concurrent.thread

class BluetoothRfcommBridge(private val context: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "PouseRfcomm"
        const val METHOD_CHANNEL_NAME = "pouse/rfcomm_control"
        const val EVENT_CHANNEL_NAME = "pouse/rfcomm_status"

        // Unique Pouse RFCOMM Service UUID
        val POUSE_RFCOMM_UUID: UUID = UUID.fromString("7f9b841a-3e2c-4a90-8b1b-5e6f8a9c0d1e")
        const val SERVICE_NAME = "Pouse RFCOMM Remote"
    }

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var serverSocket: BluetoothServerSocket? = null
    private var clientSocket: BluetoothSocket? = null
    private var outputStream: OutputStream? = null

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var isListening = false

    @Volatile
    private var isConnected = false

    init {
        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startServer" -> {
                val success = startServer()
                result.success(success)
            }
            "stopServer" -> {
                stopServer()
                result.success(true)
            }
            "getStatus" -> {
                val status = when {
                    isConnected -> "connected"
                    isListening -> "listening"
                    else -> "stopped"
                }
                result.success(status)
            }
            "sendEvent" -> {
                val message = call.argument<String>("message")
                if (message != null) {
                    val success = sendResponse(message)
                    result.success(success)
                } else {
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }

    @Synchronized
    private fun startServer(): Boolean {
        if (isListening || isConnected) {
            Log.d(TAG, "[RFCOMM] server already running")
            return true
        }
        val adapter = bluetoothAdapter
        if (adapter == null || !adapter.isEnabled) {
            Log.e(TAG, "[RFCOMM] error: Bluetooth adapter disabled or unavailable")
            emitStatus("error: bluetooth disabled")
            return false
        }

        try {
            Log.d(TAG, "[RFCOMM] server starting with UUID: $POUSE_RFCOMM_UUID")
            serverSocket = adapter.listenUsingRfcommWithServiceRecord(SERVICE_NAME, POUSE_RFCOMM_UUID)
            isListening = true
            emitStatus("listening")
            Log.d(TAG, "[RFCOMM] server ready, waiting for client connection...")

            thread(name = "PouseRfcommServerWorker") {
                runServerLoop()
            }
            return true
        } catch (e: Exception) {
            Log.e(TAG, "[RFCOMM] error starting server: ${e.message}")
            emitStatus("error: ${e.message}")
            cleanupSockets()
            return false
        }
    }

    private fun runServerLoop() {
        while (isListening) {
            try {
                val socket = serverSocket?.accept() ?: break
                Log.d(TAG, "[RFCOMM] client accepted from ${socket.remoteDevice.name} (${socket.remoteDevice.address})")
                clientSocket = socket
                outputStream = socket.outputStream
                isConnected = true
                emitStatus("connected")

                val reader = BufferedReader(InputStreamReader(socket.inputStream, Charsets.UTF_8))
                var line: String? = null

                while (isConnected && reader.readLine().also { line = it } != null) {
                    val msg = line?.trim() ?: continue
                    Log.d(TAG, "[RFCOMM] received: $msg")
                    handleMessage(msg)
                }

            } catch (e: Exception) {
                if (isListening) {
                    Log.e(TAG, "[RFCOMM] connection error or disconnect: ${e.message}")
                }
            } finally {
                isConnected = false
                outputStream = null
                clientSocket?.close()
                clientSocket = null
                Log.d(TAG, "[RFCOMM] disconnected")
                if (isListening) {
                    emitStatus("listening")
                    Log.d(TAG, "[RFCOMM] waiting for client reconnect...")
                } else {
                    emitStatus("stopped")
                }
            }
        }
    }

    private fun handleMessage(msg: String) {
        when {
            msg == "POUSE_HELLO" -> {
                sendResponse("POUSE_ACK")
            }
            msg.startsWith("TEST:") -> {
                val seq = msg.substringAfter("TEST:")
                sendResponse("ACK:$seq")
            }
            else -> {
                Log.d(TAG, "[RFCOMM] unknown message: $msg")
            }
        }
    }

    @Synchronized
    private fun sendResponse(response: String): Boolean {
        val out = outputStream ?: return false
        return try {
            val bytes = (response + "\n").toByteArray(Charsets.UTF_8)
            out.write(bytes)
            out.flush()
            true
        } catch (e: Exception) {
            Log.e(TAG, "[RFCOMM] send error: ${e.message}")
            false
        }
    }

    @Synchronized
    private fun stopServer() {
        Log.d(TAG, "[RFCOMM] server stopping...")
        isListening = false
        isConnected = false
        cleanupSockets()
        emitStatus("stopped")
    }

    private fun cleanupSockets() {
        try {
            outputStream?.close()
        } catch (ignored: Exception) {}
        outputStream = null

        try {
            clientSocket?.close()
        } catch (ignored: Exception) {}
        clientSocket = null

        try {
            serverSocket?.close()
        } catch (ignored: Exception) {}
        serverSocket = null
    }

    private fun emitStatus(status: String) {
        mainHandler.post {
            eventSink?.success(status)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val currentStatus = when {
            isConnected -> "connected"
            isListening -> "listening"
            else -> "stopped"
        }
        eventSink?.success(currentStatus)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
