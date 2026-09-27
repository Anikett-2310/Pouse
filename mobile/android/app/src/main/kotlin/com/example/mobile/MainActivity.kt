package com.example.mobile

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var btBridge: BluetoothHidBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.e("POUSE_TOUCHLESS", "POUSE_TOUCHLESS DIAGNOSTIC ACTIVE")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.e("POUSE_TOUCHLESS", "MainActivity.configureFlutterEngine executed")

        // Bluetooth HID Bridge Channels
        val bridge = BluetoothHidBridge(applicationContext, this)
        btBridge = bridge
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BluetoothHidBridge.METHOD_CHANNEL_NAME)
            .setMethodCallHandler(bridge)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, BluetoothHidBridge.EVENT_CHANNEL_NAME)
            .setStreamHandler(bridge)

        // Bluetooth RFCOMM Server POC Channels
        val rfcommBridge = BluetoothRfcommBridge(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BluetoothRfcommBridge.METHOD_CHANNEL_NAME)
            .setMethodCallHandler(rfcommBridge)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, BluetoothRfcommBridge.EVENT_CHANNEL_NAME)
            .setStreamHandler(rfcommBridge)

        // Wi-Fi Network Binder Channels
        val wifiBinder = WifiNetworkBinder(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WifiNetworkBinder.METHOD_CHANNEL_NAME)
            .setMethodCallHandler(wifiBinder)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, WifiNetworkBinder.EVENT_CHANNEL_NAME)
            .setStreamHandler(wifiBinder)

        // Touchless Camera & Hand Tracking Bridge Channels
        val touchlessBridge = TouchlessCameraBridge(applicationContext, this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TouchlessCameraBridge.METHOD_CHANNEL_NAME)
            .setMethodCallHandler(touchlessBridge)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, TouchlessCameraBridge.EVENT_CHANNEL_NAME)
            .setStreamHandler(touchlessBridge)

        // Register Touchless CameraX Preview Platform View
        flutterEngine.platformViewsController
            .registry
            .registerViewFactory(
                "pouse/touchless_camera_preview",
                TouchlessCameraViewFactory(touchlessBridge)
            )

        // Remote Screen Channels & Platform View
        val remoteScreenChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RemoteScreenBridge.METHOD_CHANNEL_NAME)
        val remoteScreenBridge = RemoteScreenBridge(applicationContext, remoteScreenChannel)
        remoteScreenChannel.setMethodCallHandler(remoteScreenBridge)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, RemoteScreenBridge.EVENT_CHANNEL_NAME)
            .setStreamHandler(remoteScreenBridge)

        flutterEngine.platformViewsController
            .registry
            .registerViewFactory(
                "pouse/remote_screen_view",
                RemoteScreenViewFactory(remoteScreenBridge)
            )
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        btBridge?.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
