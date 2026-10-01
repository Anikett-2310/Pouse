package com.pouse.app

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class BluetoothBleScannerBridge(
    private val context: Context,
    private var activity: Activity? = null
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "PouseBleScanner"
        const val METHOD_CHANNEL_NAME = "pouse/ble_scanner_control"
        const val EVENT_CHANNEL_NAME = "pouse/ble_scanner_events"
        private const val REQUEST_CODE_BLE_PERMISSIONS = 2001

        // Development BLE Company Identifier (0xFFFF is reserved by Bluetooth SIG for testing/dev).
        // For production release, replace this constant with the officially allocated Bluetooth SIG Company ID.
        const val POUSE_COMPANY_ID = 0xFFFF
        val POUSE_MAGIC = byteArrayOf(80, 79, 85, 83, 69) // "POUSE"
        const val POUSE_PROTOCOL_VERSION: Byte = 1
    }

    private var bluetoothAdapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()
    private var bleScanner: BluetoothLeScanner? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var autoStopHandler: Handler? = null

    private var isScanning = false
    private var scanCallback: ScanCallback? = null
    private val discoveredDevices = mutableMapOf<String, MutableMap<String, Any>>()

    fun setActivity(act: Activity?) {
        this.activity = act
    }

    private fun getTimestamp(): String {
        return SimpleDateFormat("HH:mm:ss.SSS", Locale.US).format(Date())
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startScan" -> {
                val success = startBleScan()
                result.success(success)
            }
            "stopScan" -> {
                stopBleScan()
                result.success(true)
            }
            "isScanning" -> {
                result.success(isScanning)
            }
            "checkPermissions" -> {
                val statusMap = checkBlePermissions()
                result.success(statusMap)
            }
            else -> result.notImplemented()
        }
    }

    private fun checkBlePermissions(): Map<String, Any> {
        val fineLocation = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val btScan = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
        } else true
        val btConnect = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        } else true

        val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        val locationServicesOn = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            lm?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true || lm?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) == true
        } else true

        val adapterEnabled = bluetoothAdapter?.isEnabled == true

        return mapOf(
            "fineLocation" to fineLocation,
            "btScan" to btScan,
            "btConnect" to btConnect,
            "locationServicesOn" to locationServicesOn,
            "adapterEnabled" to adapterEnabled
        )
    }

    @Synchronized
    private fun startBleScan(): Boolean {
        if (isScanning) {
            Log.d(TAG, "[BLE] scan already in progress. Restarting...")
            stopBleScan()
        }

        val adapter = bluetoothAdapter
        if (adapter == null || !adapter.isEnabled) {
            Log.e(TAG, "[BLE] Bluetooth adapter disabled or unavailable")
            emitState("BLUETOOTH_DISABLED")
            emitError("Bluetooth is disabled on device")
            return false
        }

        // Check Location Services on Android 10/11
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            val locEnabled = lm?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true || lm?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) == true
            if (!locEnabled) {
                Log.e(TAG, "[BLE] Location Services disabled on Android 10")
                emitState("LOCATION_REQUIRED")
                emitError("Location Services must be enabled on Android 10 to scan for BLE devices")
                return false
            }
        }

        // Check Runtime Permissions
        val permissionsToRequest = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(Manifest.permission.BLUETOOTH_SCAN)
            }
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(Manifest.permission.BLUETOOTH_CONNECT)
            }
        } else {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                permissionsToRequest.add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
        }

        if (permissionsToRequest.isNotEmpty()) {
            val act = activity
            if (act != null) {
                Log.d(TAG, "[BLE] Requesting BLE permissions: $permissionsToRequest")
                ActivityCompat.requestPermissions(act, permissionsToRequest.toTypedArray(), REQUEST_CODE_BLE_PERMISSIONS)
            } else {
                Log.e(TAG, "[BLE] Missing permissions and no Activity to request them")
            }
            emitState("PERMISSION_REQUIRED")
            emitError("Bluetooth scan permission required")
            return false
        }

        scannerInit()
        val scanner = bleScanner
        if (scanner == null) {
            Log.e(TAG, "[BLE] Failed to obtain BluetoothLeScanner")
            emitState("SCAN_ERROR")
            emitError("BLE Scanner unavailable")
            return false
        }

        discoveredDevices.clear()
        Log.d(TAG, "[BLE] scan starting...")

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult?) {
                if (result == null) return
                handleScanResult(result)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>?) {
                results?.forEach { handleScanResult(it) }
            }

            override fun onScanFailed(errorCode: Int) {
                Log.e(TAG, "[BLE] scan error: Code $errorCode")
                isScanning = false
                emitState("SCAN_ERROR")
                emitError("BLE Scan failed with code $errorCode")
            }
        }

        return try {
            scanCallback = callback
            scanner.startScan(null, settings, callback)
            isScanning = true
            emitState("SCANNING")
            emitEvent(mapOf("event" to "scan_started", "timestamp" to getTimestamp()))

            // Auto-stop scan after 12 seconds
            autoStopHandler = Handler(Looper.getMainLooper()).apply {
                postDelayed({
                    if (isScanning) {
                        Log.d(TAG, "[BLE] Auto-stopping scan after 12s timeout")
                        stopBleScan()
                    }
                }, 12000)
            }

            true
        } catch (e: Exception) {
            Log.e(TAG, "[BLE] Exception starting scan: ${e.message}")
            isScanning = false
            emitState("SCAN_ERROR")
            emitError("Exception starting scan: ${e.message}")
            false
        }
    }

    private fun scannerInit() {
        if (bleScanner == null) {
            bleScanner = bluetoothAdapter?.bluetoothLeScanner
        }
    }

    @Synchronized
    private fun stopBleScan() {
        if (!isScanning) return
        Log.d(TAG, "[BLE] scan stopping...")

        autoStopHandler?.removeCallbacksAndMessages(null)
        autoStopHandler = null

        val scanner = bleScanner
        val callback = scanCallback
        if (scanner != null && callback != null) {
            try {
                scanner.stopScan(callback)
            } catch (e: Exception) {
                Log.e(TAG, "[BLE] Error stopping scanner: ${e.message}")
            }
        }

        scanCallback = null
        isScanning = false
        emitState(if (discoveredDevices.isNotEmpty()) "DEVICES_FOUND" else "NO_DEVICES_FOUND")
        emitEvent(mapOf("event" to "scan_stopped", "timestamp" to getTimestamp()))
        Log.d(TAG, "[BLE] scan stopped.")
    }

    private fun handleScanResult(result: ScanResult) {
        val device = result.device ?: return
        val address = device.address ?: return
        val record = result.scanRecord
        val rssi = result.rssi
        val ts = getTimestamp()

        var isMatchedPouse = false
        var classicBdAddr: String? = null
        var deviceName = device.name ?: record?.deviceName ?: "Pouse PC"

        if (record != null) {
            // Check SparseArray Manufacturer Data
            val mfrBytes = record.getManufacturerSpecificData(POUSE_COMPANY_ID)
            if (mfrBytes != null && mfrBytes.size >= 6) {
                if (mfrBytes[0] == POUSE_MAGIC[0] &&
                    mfrBytes[1] == POUSE_MAGIC[1] &&
                    mfrBytes[2] == POUSE_MAGIC[2] &&
                    mfrBytes[3] == POUSE_MAGIC[3] &&
                    mfrBytes[4] == POUSE_MAGIC[4] &&
                    mfrBytes[5] == POUSE_PROTOCOL_VERSION) {
                    isMatchedPouse = true
                    if (mfrBytes.size >= 12) {
                        classicBdAddr = String.format(
                            Locale.US,
                            "%02X:%02X:%02X:%02X:%02X:%02X",
                            mfrBytes[6], mfrBytes[7], mfrBytes[8],
                            mfrBytes[9], mfrBytes[10], mfrBytes[11]
                        )
                    }
                }
            }

            // Fallback raw bytes scan if SparseArray was not parsed by OS
            if (!isMatchedPouse && record.bytes != null) {
                val rawMatch = matchRawPayload(record.bytes)
                if (rawMatch != null) {
                    isMatchedPouse = true
                    if (rawMatch.isNotEmpty()) {
                        classicBdAddr = rawMatch
                    }
                }
            }
        }

        if (isMatchedPouse && (deviceName == "Pouse PC" || deviceName.isEmpty())) {
            deviceName = "${device.name ?: "AXTPC"} (Pouse BLE)"
        }

        // Deduplicate & update existing entry
        val isNewDevice = !discoveredDevices.containsKey(address)
        val deviceMap = discoveredDevices.getOrPut(address) { mutableMapOf() }
        deviceMap["name"] = deviceName
        deviceMap["bleAddress"] = address
        if (classicBdAddr != null) deviceMap["classicAddress"] = classicBdAddr
        deviceMap["address"] = classicBdAddr ?: address
        deviceMap["rssi"] = rssi
        deviceMap["matched"] = isMatchedPouse
        deviceMap["timestamp"] = ts

        Log.d(TAG, "[BLE] discovered LE address: $address")
        if (!classicBdAddr.isNullOrEmpty()) {
            Log.d(TAG, "[BLE] decoded Classic BD_ADDR: $classicBdAddr")
        }

        if (isMatchedPouse) {
            Log.d(TAG, "[BLE] matched Pouse PC: $deviceName (Classic: $classicBdAddr, BLE: $address) | RSSI: $rssi dBm")
        } else {
            Log.d(TAG, "[BLE] duplicate advertisement ignored / updated: $deviceName ($address) | RSSI: $rssi")
        }

        val eventPayload = mutableMapOf<String, Any>(
            "event" to "pc_discovered",
            "name" to deviceName,
            "bleAddress" to address,
            "address" to (classicBdAddr ?: address),
            "rssi" to rssi,
            "matched" to isMatchedPouse,
            "isNew" to isNewDevice,
            "timestamp" to ts
        )
        if (!classicBdAddr.isNullOrEmpty()) {
            eventPayload["classicAddress"] = classicBdAddr
        }

        emitEvent(eventPayload)
    }

    private fun matchRawPayload(bytes: ByteArray): String? {
        val companyIdLow = POUSE_COMPANY_ID and 0xFF
        val companyIdHigh = (POUSE_COMPANY_ID shr 8) and 0xFF
        // Search raw BLE advertisement packet bytes for POUSE_COMPANY_ID (little-endian) + "POUSE" + 0x01
        for (i in 0 until bytes.size - 8) {
            if ((bytes[i].toInt() and 0xFF) == companyIdLow && (bytes[i + 1].toInt() and 0xFF) == companyIdHigh) {
                if (bytes[i + 2] == POUSE_MAGIC[0] &&
                    bytes[i + 3] == POUSE_MAGIC[1] &&
                    bytes[i + 4] == POUSE_MAGIC[2] &&
                    bytes[i + 5] == POUSE_MAGIC[3] &&
                    bytes[i + 6] == POUSE_MAGIC[4] &&
                    bytes[i + 7] == POUSE_PROTOCOL_VERSION) {
                    if (i + 13 < bytes.size) {
                        return String.format(
                            Locale.US,
                            "%02X:%02X:%02X:%02X:%02X:%02X",
                            bytes[i + 8], bytes[i + 9], bytes[i + 10],
                            bytes[i + 11], bytes[i + 12], bytes[i + 13]
                        )
                    }
                    return ""
                }
            }
        }
        return null
    }

    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == REQUEST_CODE_BLE_PERMISSIONS) {
            val allGranted = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            if (allGranted) {
                Log.d(TAG, "[BLE] Permissions granted. Starting BLE scan...")
                startBleScan()
            } else {
                Log.e(TAG, "[BLE] permission required")
                emitState("PERMISSION_REQUIRED")
                emitError("BLE scan permission was denied")
            }
        }
    }

    private fun emitState(state: String) {
        emitEvent(mapOf(
            "event" to "state_changed",
            "state" to state,
            "timestamp" to getTimestamp()
        ))
    }

    private fun emitError(msg: String) {
        emitEvent(mapOf(
            "event" to "error",
            "message" to msg,
            "timestamp" to getTimestamp()
        ))
    }

    private fun emitEvent(data: Map<String, Any>) {
        mainHandler.post {
            eventSink?.success(data)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val initialState = when {
            isScanning -> "SCANNING"
            discoveredDevices.isNotEmpty() -> "DEVICES_FOUND"
            else -> "IDLE"
        }
        emitState(initialState)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
