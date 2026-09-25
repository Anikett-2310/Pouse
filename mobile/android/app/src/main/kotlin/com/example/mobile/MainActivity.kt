package com.example.mobile

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.e("POUSE_TOUCHLESS", "POUSE_TOUCHLESS DIAGNOSTIC ACTIVE")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.e("POUSE_TOUCHLESS", "MainActivity.configureFlutterEngine executed")

        // Bluetooth HID Bridge Channels
        val btBridge = BluetoothHidBridge(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BluetoothHidBridge.METHOD_CHANNEL_NAME)
            .setMethodCallHandler(btBridge)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, BluetoothHidBridge.EVENT_CHANNEL_NAME)
            .setStreamHandler(btBridge)

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
    }
}
