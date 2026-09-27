package com.example.mobile

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class WifiNetworkBinder(private val context: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "PouseWifiBinder"
        const val METHOD_CHANNEL_NAME = "pouse/wifi_control"
        const val EVENT_CHANNEL_NAME = "pouse/wifi_status"
    }

    private val connectivityManager: ConnectivityManager? =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile
    private var boundWifiNetwork: Network? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "bindWifiNetwork" -> {
                val success = requestAndBindWifiNetwork()
                result.success(success)
            }
            "unbindWifiNetwork" -> {
                unbindWifiNetwork()
                result.success(true)
            }
            "isWifiConnected" -> {
                result.success(boundWifiNetwork != null || isWifiNetworkAvailable())
            }
            else -> result.notImplemented()
        }
    }

    @Synchronized
    private fun requestAndBindWifiNetwork(): Boolean {
        val cm = connectivityManager
        if (cm == null) {
            Log.e(TAG, "[WIFI_BINDER] ConnectivityManager unavailable")
            emitStatus("wifi_unavailable")
            return false
        }

        // Check active network first for immediate binding
        val activeNetwork = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            cm.activeNetwork
        } else {
            null
        }

        if (activeNetwork != null) {
            val caps = cm.getNetworkCapabilities(activeNetwork)
            if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                Log.d(TAG, "[WIFI_BINDER] Immediately binding active Wi-Fi Network: $activeNetwork")
                boundWifiNetwork = activeNetwork
                bindProcess(activeNetwork)
                emitStatus("wifi_bound")
            }
        }

        try {
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .build()

            cleanupCallback()

            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    super.onAvailable(network)
                    Log.d(TAG, "[WIFI_BINDER] Wi-Fi Network available: $network. Binding process sockets...")
                    boundWifiNetwork = network
                    bindProcess(network)
                    emitStatus("wifi_bound")
                }

                override fun onLost(network: Network) {
                    super.onLost(network)
                    Log.d(TAG, "[WIFI_BINDER] Wi-Fi Network lost: $network. Resetting process socket binding.")
                    if (boundWifiNetwork == network) {
                        boundWifiNetwork = null
                        bindProcess(null)
                        emitStatus("wifi_lost")
                    }
                }

                override fun onUnavailable() {
                    super.onUnavailable()
                    Log.d(TAG, "[WIFI_BINDER] Wi-Fi Network request unavailable.")
                    boundWifiNetwork = null
                    bindProcess(null)
                    emitStatus("wifi_unavailable")
                }
            }

            networkCallback = callback
            cm.requestNetwork(request, callback)
            return true
        } catch (e: Exception) {
            Log.e(TAG, "[WIFI_BINDER] Error requesting Wi-Fi network: ${e.message}")
            if (boundWifiNetwork == null) {
                emitStatus("wifi_unavailable")
            }
            return boundWifiNetwork != null
        }
    }

    private fun isWifiNetworkAvailable(): Boolean {
        val cm = connectivityManager ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val network = cm.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(network) ?: return false
            return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
        } else {
            @Suppress("DEPRECATION")
            val info = cm.activeNetworkInfo ?: return false
            @Suppress("DEPRECATION")
            return info.type == ConnectivityManager.TYPE_WIFI && info.isConnected
        }
    }

    @Synchronized
    private fun unbindWifiNetwork() {
        Log.d(TAG, "[WIFI_BINDER] Unbinding Wi-Fi network and cleaning up process binding.")
        boundWifiNetwork = null
        bindProcess(null)
        cleanupCallback()
        emitStatus("wifi_unbound")
    }

    private fun bindProcess(network: Network?) {
        val cm = connectivityManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                cm.bindProcessToNetwork(network)
            } else {
                @Suppress("DEPRECATION")
                ConnectivityManager.setProcessDefaultNetwork(network)
            }
        } catch (e: Exception) {
            Log.e(TAG, "[WIFI_BINDER] Error setting process default network: ${e.message}")
        }
    }

    private fun cleanupCallback() {
        val cm = connectivityManager
        val cb = networkCallback
        if (cm != null && cb != null) {
            try {
                cm.unregisterNetworkCallback(cb)
            } catch (e: Exception) {
                Log.e(TAG, "[WIFI_BINDER] Error unregistering callback: ${e.message}")
            }
        }
        networkCallback = null
    }

    private fun emitStatus(status: String) {
        mainHandler.post {
            eventSink?.success(status)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val currentStatus = if (boundWifiNetwork != null || isWifiNetworkAvailable()) "wifi_bound" else "wifi_unavailable"
        eventSink?.success(currentStatus)
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
