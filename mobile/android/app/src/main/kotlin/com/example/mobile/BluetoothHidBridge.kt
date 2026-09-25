package com.example.mobile

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

class BluetoothHidBridge(private val context: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "PouseBluetoothHid"
        const val METHOD_CHANNEL_NAME = "pouse/bluetooth_control"
        const val EVENT_CHANNEL_NAME = "pouse/bluetooth_status"

        const val REPORT_ID_MOUSE = 1
        const val REPORT_ID_KEYBOARD = 2

        val HID_DESCRIPTOR = byteArrayOf(
            // --- MOUSE (Report ID 1) ---
            0x05.toByte(), 0x01.toByte(), // USAGE_PAGE (Generic Desktop)
            0x09.toByte(), 0x02.toByte(), // USAGE (Mouse)
            0xA1.toByte(), 0x01.toByte(), // COLLECTION (Application)
            0x85.toByte(), 0x01.toByte(), //   REPORT_ID (1)
            0x09.toByte(), 0x01.toByte(), //   USAGE (Pointer)
            0xA1.toByte(), 0x00.toByte(), //   COLLECTION (Physical)
            0x05.toByte(), 0x09.toByte(), //     USAGE_PAGE (Button)
            0x19.toByte(), 0x01.toByte(), //     USAGE_MINIMUM (Button 1)
            0x29.toByte(), 0x03.toByte(), //     USAGE_MAXIMUM (Button 3)
            0x15.toByte(), 0x00.toByte(), //     LOGICAL_MINIMUM (0)
            0x25.toByte(), 0x01.toByte(), //     LOGICAL_MAXIMUM (1)
            0x95.toByte(), 0x03.toByte(), //     REPORT_COUNT (3)
            0x75.toByte(), 0x01.toByte(), //     REPORT_SIZE (1)
            0x81.toByte(), 0x02.toByte(), //     INPUT (Data,Var,Abs)
            0x95.toByte(), 0x01.toByte(), //     REPORT_COUNT (1)
            0x75.toByte(), 0x05.toByte(), //     REPORT_SIZE (5)
            0x81.toByte(), 0x03.toByte(), //     INPUT (Cnst,Var,Abs)
            0x05.toByte(), 0x01.toByte(), //     USAGE_PAGE (Generic Desktop)
            0x09.toByte(), 0x30.toByte(), //     USAGE (X)
            0x09.toByte(), 0x31.toByte(), //     USAGE (Y)
            0x09.toByte(), 0x38.toByte(), //     USAGE (Wheel)
            0x15.toByte(), 0x81.toByte(), //     LOGICAL_MINIMUM (-127)
            0x25.toByte(), 0x7F.toByte(), //     LOGICAL_MAXIMUM (127)
            0x75.toByte(), 0x08.toByte(), //     REPORT_SIZE (8)
            0x95.toByte(), 0x03.toByte(), //     REPORT_COUNT (3)
            0x81.toByte(), 0x06.toByte(), //     INPUT (Data,Var,Rel)
            0xC0.toByte(),                //   END_COLLECTION
            0xC0.toByte(),                // END_COLLECTION

            // --- KEYBOARD (Report ID 2) ---
            0x05.toByte(), 0x01.toByte(), // USAGE_PAGE (Generic Desktop)
            0x09.toByte(), 0x06.toByte(), // USAGE (Keyboard)
            0xA1.toByte(), 0x01.toByte(), // COLLECTION (Application)
            0x85.toByte(), 0x02.toByte(), //   REPORT_ID (2)
            0x05.toByte(), 0x07.toByte(), //   USAGE_PAGE (Keyboard)
            0x19.toByte(), 0xE0.toByte(), //   USAGE_MINIMUM (Keyboard LeftControl)
            0x29.toByte(), 0xE7.toByte(), //   USAGE_MAXIMUM (Keyboard Right GUI)
            0x15.toByte(), 0x00.toByte(), //   LOGICAL_MINIMUM (0)
            0x25.toByte(), 0x01.toByte(), //   LOGICAL_MAXIMUM (1)
            0x75.toByte(), 0x01.toByte(), //   REPORT_SIZE (1)
            0x95.toByte(), 0x08.toByte(), //   REPORT_COUNT (8)
            0x81.toByte(), 0x02.toByte(), //   INPUT (Data,Var,Abs)
            0x95.toByte(), 0x01.toByte(), //   REPORT_COUNT (1)
            0x75.toByte(), 0x08.toByte(), //   REPORT_SIZE (8)
            0x81.toByte(), 0x03.toByte(), //   INPUT (Cnst,Var,Abs)
            0x95.toByte(), 0x06.toByte(), //   REPORT_COUNT (6)
            0x75.toByte(), 0x08.toByte(), //   REPORT_SIZE (8)
            0x15.toByte(), 0x00.toByte(), //   LOGICAL_MINIMUM (0)
            0x25.toByte(), 0x65.toByte(), //   LOGICAL_MAXIMUM (101)
            0x05.toByte(), 0x07.toByte(), //   USAGE_PAGE (Keyboard)
            0x19.toByte(), 0x00.toByte(), //   USAGE_MINIMUM (Reserved)
            0x29.toByte(), 0x65.toByte(), //   USAGE_MAXIMUM (Keyboard Application)
            0x81.toByte(), 0x00.toByte(), //   INPUT (Data,Ary,Abs)
            0xC0.toByte()                 // END_COLLECTION
        )
    }

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var hidDeviceProxy: BluetoothProfile? = null
    private var connectedDevice: BluetoothDevice? = null
    private var eventSink: EventChannel.EventSink? = null
    private var isRegistered = false

    init {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
            initHidProfile()
        }
    }

    private fun initHidProfile() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || bluetoothAdapter == null) return

        try {
            bluetoothAdapter?.getProfileProxy(context, object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile?) {
                    if (profile == BluetoothProfile.HID_DEVICE) {
                        hidDeviceProxy = proxy
                        registerHidApp()
                    }
                }

                override fun onServiceDisconnected(profile: Int) {
                    if (profile == BluetoothProfile.HID_DEVICE) {
                        hidDeviceProxy = null
                        isRegistered = false
                        connectedDevice = null
                        emitStatus("disconnected")
                    }
                }
            }, BluetoothProfile.HID_DEVICE)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get HID profile proxy: ${e.message}")
        }
    }

    private fun registerHidApp() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
        val hidDevice = hidDeviceProxy as? BluetoothHidDevice ?: return

        val sdpSettings = BluetoothHidDeviceAppSdpSettings(
            "Pouse Remote",
            "Pouse",
            "Pouse Combo Remote",
            BluetoothHidDevice.SUBCLASS1_COMBO,
            HID_DESCRIPTOR
        )

        try {
            hidDevice.registerApp(
                sdpSettings,
                null,
                null,
                context.mainExecutor,
                object : BluetoothHidDevice.Callback() {
                    override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
                        isRegistered = registered
                        Log.d(TAG, "HID App registration changed: registered=$registered")
                    }

                    override fun onConnectionStateChanged(device: BluetoothDevice?, state: Int) {
                        when (state) {
                            BluetoothProfile.STATE_CONNECTED -> {
                                connectedDevice = device
                                emitStatus("connected")
                            }
                            BluetoothProfile.STATE_CONNECTING -> {
                                emitStatus("connecting")
                            }
                            BluetoothProfile.STATE_DISCONNECTED -> {
                                connectedDevice = null
                                emitStatus("disconnected")
                            }
                        }
                    }
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register HID App: ${e.message}")
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> {
                val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                        context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH)
                result.success(supported)
            }
            "getPairedDevices" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || bluetoothAdapter == null) {
                    result.success(emptyList<Map<String, String>>())
                    return
                }
                try {
                    val pairedList = bluetoothAdapter?.bondedDevices?.map { dev ->
                        mapOf("name" to (dev.name ?: "Unknown"), "address" to dev.address)
                    } ?: emptyList()
                    result.success(pairedList)
                } catch (e: Exception) {
                    result.error("PERM_ERROR", "Permission error reading paired devices: ${e.message}", null)
                }
            }
            "connect" -> {
                val address = call.argument<String>("address")
                if (address.isNullOrEmpty() || Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                    result.success(false)
                    return
                }
                val hidDevice = hidDeviceProxy as? BluetoothHidDevice
                val device = bluetoothAdapter?.getRemoteDevice(address)
                if (hidDevice != null && device != null) {
                    emitStatus("connecting")
                    val success = hidDevice.connect(device)
                    result.success(success)
                } else {
                    result.success(false)
                }
            }
            "disconnect" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && connectedDevice != null) {
                    val hidDevice = hidDeviceProxy as? BluetoothHidDevice
                    hidDevice?.disconnect(connectedDevice)
                }
                connectedDevice = null
                emitStatus("disconnected")
                result.success(true)
            }
            "sendMouseReport" -> {
                val button = call.argument<Int>("button") ?: 0
                val dx = call.argument<Int>("dx") ?: 0
                val dy = call.argument<Int>("dy") ?: 0
                val wheel = call.argument<Int>("wheel") ?: 0

                val success = sendMouseReportSplit(button, dx, dy, wheel)
                result.success(success)
            }
            "sendKeyboardReport" -> {
                val modifiers = call.argument<Int>("modifiers") ?: 0
                val keycodesList = call.argument<List<Int>>("keycodes") ?: emptyList()

                val success = sendKeyboardReportInternal(modifiers, keycodesList)
                result.success(success)
            }
            "releaseAll" -> {
                releaseAllInternal()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun sendMouseReportSplit(button: Int, dx: Int, dy: Int, wheel: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        val hidDevice = hidDeviceProxy as? BluetoothHidDevice ?: return false
        val device = connectedDevice ?: return false

        var remainingDx = dx
        var remainingDy = dy
        var remainingWheel = wheel
        var overallSuccess = true

        // Split large deltas exceeding int8 (-127 to +127) into multiple consecutive HID reports
        while (remainingDx != 0 || remainingDy != 0 || remainingWheel != 0) {
            val stepDx = remainingDx.coerceIn(-127, 127)
            val stepDy = remainingDy.coerceIn(-127, 127)
            val stepWheel = remainingWheel.coerceIn(-127, 127)

            remainingDx -= stepDx
            remainingDy -= stepDy
            remainingWheel -= stepWheel

            val report = byteArrayOf(
                button.toByte(),
                stepDx.toByte(),
                stepDy.toByte(),
                stepWheel.toByte()
            )

            val sent = hidDevice.sendReport(device, REPORT_ID_MOUSE, report)
            if (!sent) overallSuccess = false
        }

        // If no movement delta, send stationary button state report
        if (dx == 0 && dy == 0 && wheel == 0) {
            val report = byteArrayOf(button.toByte(), 0, 0, 0)
            overallSuccess = hidDevice.sendReport(device, REPORT_ID_MOUSE, report)
        }

        return overallSuccess
    }

    private fun sendKeyboardReportInternal(modifiers: Int, keycodesList: List<Int>): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        val hidDevice = hidDeviceProxy as? BluetoothHidDevice ?: return false
        val device = connectedDevice ?: return false

        val keyBytes = ByteArray(6) { 0 }
        for (i in 0 until minOf(keycodesList.size, 6)) {
            keyBytes[i] = keycodesList[i].toByte()
        }

        val report = byteArrayOf(
            modifiers.toByte(),
            0x00.toByte(),
            keyBytes[0], keyBytes[1], keyBytes[2], keyBytes[3], keyBytes[4], keyBytes[5]
        )

        return hidDevice.sendReport(device, REPORT_ID_KEYBOARD, report)
    }

    private fun releaseAllInternal() {
        sendMouseReportSplit(0, 0, 0, 0)
        sendKeyboardReportInternal(0, emptyList())
    }

    private fun emitStatus(status: String) {
        eventSink?.success(status)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val currentStatus = when {
            connectedDevice != null -> "connected"
            else -> "disconnected"
        }
        eventSink?.success(currentStatus)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
