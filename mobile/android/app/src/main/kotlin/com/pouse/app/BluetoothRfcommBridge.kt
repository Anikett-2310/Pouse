package com.pouse.app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

/**
 * Production Bluetooth RFCOMM Client Bridge for Pouse.
 *
 * Connects securely to the Windows Pouse RFCOMM Server using UUID:
 * 7f9b841a-3e2c-4a90-8b1b-5e6f8a9c0d1e
 *
 * Executes connection off the main UI thread, conducts the POUSE_HELLO / POUSE_ACK
 * handshake, listens for bond state transitions (pairing), streams PouseEvents,
 * and cleanly handles disconnects and error recovery.
 */
class BluetoothRfcommBridge(private val context: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "PouseRfcomm"
        const val METHOD_CHANNEL_NAME = "pouse/rfcomm_control"
        const val EVENT_CHANNEL_NAME = "pouse/rfcomm_status"

        // Unique Pouse RFCOMM Service UUID (shared with Windows Pouse server)
        val POUSE_RFCOMM_UUID: UUID = UUID.fromString("7f9b841a-3e2c-4a90-8b1b-5e6f8a9c0d1e")
    }

    private val bluetoothAdapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()
    private var clientSocket: BluetoothSocket? = null
    private var outputStream: OutputStream? = null
    private var workerThread: Thread? = null

    /**
     * Background socket writer — keeps all RFCOMM I/O off the Android main thread.
     *
     * The previous implementation called outputStream.write() + flush() directly from
     * sendEvent(), which was invoked via MethodChannel on the Android main (platform)
     * thread. Blocking socket I/O on the main thread stalls Flutter's rendering pipeline
     * for the duration of each write, adding up to several milliseconds of latency per
     * MOVE event at 60Hz.
     *
     * This writer thread owns the socket output. sendEvent() enqueues message bytes
     * (non-blocking) and returns immediately. The writer drains the queue and does the
     * actual write + flush off the main thread.
     *
     * MOVE events use offer() with no timeout (drop if queue is full at capacity).
     * Discrete events (click, key, button) use offer() with a short timeout so they
     * are never silently dropped.
     *
     * The queue capacity is set to 64 messages. At 60 MOVE events/sec with sub-ms
     * dequeue latency this is never full under normal conditions; the safety valve
     * prevents unbounded memory growth if the socket write blocks.
     */
    private var socketWriter: PouseSocketWriter? = null

    /** Sampled latency statistics for enqueue→write timing. Printed every 5s. */
    private val latencyStats = BluetoothLatencyStats()

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var isConnected = false

    @Volatile
    private var isConnecting = false

    @Volatile
    private var isPairing = false

    /** Set to true BEFORE closing the socket on an intentional user-driven disconnect.
     *  The read loop checks this flag so it does not emit an error status when the
     *  socket is closed on purpose. Cleared at the start of each new connect attempt. */
    @Volatile
    private var intentionalDisconnect = false

    /** Monotonically increasing counter; incremented on every new connect() call.
     *  Each worker thread captures its own generation value and drops emits that
     *  are no longer current (stale callbacks from a superseded attempt). */
    private val connectionGeneration = AtomicInteger(0)

    @Volatile
    private var currentStatus = "idle"

    @Volatile
    private var targetAddress: String? = null

    @Volatile
    private var targetDeviceName: String? = null

    private var receiverRegistered = false

    private val bluetoothReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            when (action) {
                BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                    val device: BluetoothDevice? = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    if (device == null || (targetAddress != null && device.address != targetAddress)) {
                        return
                    }
                    val bondState = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.BOND_NONE)
                    val prevBondState = intent.getIntExtra(BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE, BluetoothDevice.BOND_NONE)

                    when (bondState) {
                        BluetoothDevice.BOND_BONDING -> {
                            Log.d(TAG, "[BT] bonding / pairing started with ${device.name ?: device.address}")
                            isPairing = true
                            emitStatus("pairing")
                        }
                        BluetoothDevice.BOND_BONDED -> {
                            Log.d(TAG, "[BT] bonding completed / paired with ${device.name ?: device.address}")
                            isPairing = false
                            if (isConnecting) {
                                emitStatus("connecting")
                            }
                        }
                        BluetoothDevice.BOND_NONE -> {
                            if (prevBondState == BluetoothDevice.BOND_BONDING) {
                                Log.w(TAG, "[BT] pairing cancelled or rejected")
                                isPairing = false
                                emitStatus("pairing_cancelled")
                            }
                        }
                    }
                }
                BluetoothAdapter.ACTION_STATE_CHANGED -> {
                    val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                    if (state == BluetoothAdapter.STATE_TURNING_OFF || state == BluetoothAdapter.STATE_OFF) {
                        Log.w(TAG, "[BT] bluetooth disabled by system")
                        handleDisconnect("Bluetooth turned off")
                    }
                }
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connect" -> {
                val address = call.argument<String>("address")
                val name = call.argument<String>("name")
                if (address.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENT", "Address must not be null or empty", null)
                    return
                }
                connect(address, name, result)
            }
            "disconnect" -> {
                disconnect()
                result.success(true)
            }
            "getStatus" -> {
                result.success(currentStatus)
            }
            "sendEvent" -> {
                val message = call.argument<String>("message")
                if (message != null) {
                    val success = sendEvent(message)
                    result.success(success)
                } else {
                    result.success(false)
                }
            }
            // Compatibility shim for legacy startServer calls
            "startServer" -> {
                val addr = targetAddress
                if (addr != null) {
                    connect(addr, targetDeviceName, result)
                } else {
                    result.success(false)
                }
            }
            // Compatibility shim for legacy stopServer calls
            "stopServer" -> {
                disconnect()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    @Synchronized
    private fun connect(address: String, name: String?, result: MethodChannel.Result) {
        val adapter = bluetoothAdapter
        if (adapter == null || !adapter.isEnabled) {
            Log.e(TAG, "[BT] error: Bluetooth adapter disabled or unavailable")
            emitStatus("error: bluetooth disabled")
            result.success(false)
            return
        }

        if (isConnected && targetAddress == address) {
            Log.d(TAG, "[BT] already connected to $address")
            result.success(true)
            return
        }

        // Clean up previous connection if in progress or connected
        if (isConnecting || isConnected) {
            cleanup(notifyDisconnected = false)
        }

        // Reset intentional-disconnect flag and bump generation for this attempt
        intentionalDisconnect = false
        val generation = connectionGeneration.incrementAndGet()

        targetAddress = address
        targetDeviceName = name
        isConnecting = true
        emitStatus("connecting")

        registerReceivers()

        val devName = name ?: address
        Log.d(TAG, "[BT] connecting to $devName ($address)")
        Log.d(TAG, "[BT] connecting using Classic BD_ADDR: $address")

        val thread = thread(name = "PouseRfcommClientWorker") {
            executeConnectFlow(address, devName, generation)
        }
        workerThread = thread

        result.success(true)
    }

    private fun executeConnectFlow(address: String, devName: String, generation: Int) {
        val adapter = bluetoothAdapter
        if (adapter == null || !adapter.isEnabled) {
            emitIfCurrentGeneration(generation) { handleConnectFailure("Bluetooth adapter disabled") }
            return
        }

        try {
            val device = adapter.getRemoteDevice(address)

            // Cancel any in-progress BLE or Classic discovery as required by Android Bluetooth docs
            if (adapter.isDiscovering) {
                adapter.cancelDiscovery()
                Log.d(TAG, "[BT] cancelled discovery prior to RFCOMM connection")
            }

            // Create SECURE RFCOMM socket
            Log.d(TAG, "[BT] secure RFCOMM socket created")
            val socket = device.createRfcommSocketToServiceRecord(POUSE_RFCOMM_UUID)
            clientSocket = socket

            // Perform blocking connect off main thread
            Log.d(TAG, "[BT] RFCOMM connect started")
            socket.connect()

            // Generation check: if a newer connect() superseded us, bail silently
            if (connectionGeneration.get() != generation) {
                Log.d(TAG, "[BT] superseded by newer connection attempt (gen $generation), dropping")
                try { socket.close() } catch (_: Exception) {}
                return
            }

            Log.d(TAG, "[BT] RFCOMM connected")
            val out = socket.outputStream
            outputStream = out

            // Start background writer thread to keep socket I/O off the main thread.
            val writer = PouseSocketWriter(out, latencyStats)
            socketWriter = writer
            writer.start()

            val reader = BufferedReader(InputStreamReader(socket.inputStream, Charsets.UTF_8))

            // Handshake: Send POUSE_HELLO\n
            Log.d(TAG, "[BT] HELLO sent")
            out.write("POUSE_HELLO\n".toByteArray(Charsets.UTF_8))
            out.flush()

            // Handshake: Expect POUSE_ACK\n
            val firstLine = reader.readLine()
            val ackLine = firstLine?.trim()
            if (ackLine == "POUSE_ACK") {
                Log.d(TAG, "[BT] ACK received")
                Log.d(TAG, "[BT] bluetooth transport connected")
                isConnected = true
                isConnecting = false
                isPairing = false
                emitStatus("connected")
            } else {
                Log.e(TAG, "[BT] handshake failed: expected POUSE_ACK, received '$ackLine'")
                emitIfCurrentGeneration(generation) { handleConnectFailure("Handshake failed") }
                return
            }

            // Continuous read loop for incoming status or error messages
            var line: String? = null
            while (isConnected && reader.readLine().also { line = it } != null) {
                val msg = line?.trim() ?: continue
                if (msg.isEmpty()) continue

                if (msg == "POUSE_ACK") {
                    Log.d(TAG, "[BT] ACK received (keepalive)")
                } else if (msg.startsWith("ACK:")) {
                    Log.d(TAG, "[BT] ACK sequence: ${msg.substringAfter("ACK:")}")
                } else {
                    Log.d(TAG, "[BT] received from PC: $msg")
                }
            }

        } catch (e: Exception) {
            val msg = e.message ?: "Socket connection failed"

            // Intentional disconnect: socket was closed by the user. Do not emit an error.
            if (intentionalDisconnect) {
                Log.d(TAG, "[BT] read loop exited after intentional disconnect — not an error")
                return
            }

            if (isPairing) {
                Log.w(TAG, "[BT] pairing cancelled")
                emitStatus("pairing_cancelled")
            } else {
                Log.e(TAG, "[BT] socket error: $msg")
            }
            emitIfCurrentGeneration(generation) { handleConnectFailure(msg) }
            return
        }

        // Socket closed cleanly (EOF). Only notify a real remote disconnect if it was not intentional.
        if (intentionalDisconnect) {
            Log.d(TAG, "[BT] read loop exited after intentional disconnect (EOF path)")
        } else {
            handleDisconnect("Socket closed by remote PC")
        }
    }

    /**
     * Runs [block] only when [generation] still matches the current [connectionGeneration],
     * i.e. no newer connect() has superseded this attempt. Stale callbacks are silently dropped.
     */
    private inline fun emitIfCurrentGeneration(generation: Int, block: () -> Unit) {
        if (connectionGeneration.get() == generation) {
            block()
        } else {
            Log.d(TAG, "[BT] dropping stale callback for superseded generation $generation")
        }
    }

    private fun handleConnectFailure(reason: String) {
        isConnecting = false
        isConnected = false
        isPairing = false
        cleanup(notifyDisconnected = false)
        emitStatus("error: $reason")
    }

    private fun handleDisconnect(reason: String) {
        if (!isConnected && !isConnecting) return
        Log.d(TAG, "[BT] disconnected ($reason)")
        cleanup(notifyDisconnected = true)
    }

    @Synchronized
    private fun disconnect() {
        Log.d(TAG, "[BT] disconnecting...")
        // Mark as intentional BEFORE closing the socket so the read-loop exception
        // (or EOF) is not misinterpreted as an unexpected failure.
        intentionalDisconnect = true
        emitStatus("disconnecting")
        cleanup(notifyDisconnected = true)
    }

    private fun cleanup(notifyDisconnected: Boolean) {
        isConnecting = false
        isConnected = false
        isPairing = false

        // Stop the background writer thread first so it can flush pending bytes
        // before we close the socket.
        socketWriter?.stop()
        socketWriter = null

        unregisterReceivers()

        try {
            outputStream?.close()
        } catch (ignored: Exception) {}
        outputStream = null

        try {
            clientSocket?.close()
        } catch (ignored: Exception) {}
        clientSocket = null

        workerThread = null

        if (notifyDisconnected) {
            emitStatus("disconnected")
        }
    }

    /**
     * Enqueue a JSON message for delivery to the Windows RFCOMM server.
     *
     * Returns true if the message was accepted into the writer queue.
     * Returns false if the socket is not connected or the writer queue is full
     * (only possible for MOVE events in pathological cases).
     *
     * All blocking I/O happens on the PouseSocketWriter background thread,
     * never on the Android main thread.
     */
    fun sendEvent(message: String): Boolean {
        val writer = socketWriter ?: return false
        return writer.enqueue(message, isMoveEvent = message.contains("\"MOVE\""))
    }

    private fun registerReceivers() {
        if (!receiverRegistered) {
            val filter = IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
                addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            }
            try {
                context.registerReceiver(bluetoothReceiver, filter)
                receiverRegistered = true
            } catch (e: Exception) {
                Log.e(TAG, "[BT] error registering broadcast receiver: ${e.message}")
            }
        }
    }

    private fun unregisterReceivers() {
        if (receiverRegistered) {
            try {
                context.unregisterReceiver(bluetoothReceiver)
            } catch (ignored: Exception) {}
            receiverRegistered = false
        }
    }

    private fun emitStatus(status: String) {
        currentStatus = status
        mainHandler.post {
            eventSink?.success(status)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        eventSink?.success(currentStatus)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
