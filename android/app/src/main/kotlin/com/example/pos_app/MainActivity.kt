package com.example.pos_app

import android.provider.Settings
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "jmsolution.posapp/device_identity",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceId" -> {
                    val androidId = Settings.Secure.getString(
                        contentResolver,
                        Settings.Secure.ANDROID_ID,
                    )
                    result.success(androidId)
                }
                "getDeviceName" -> {
                    val manufacturer = Build.MANUFACTURER.trim()
                    val model = Build.MODEL.trim()
                    val deviceName = listOf(manufacturer, model)
                        .filter { it.isNotEmpty() }
                        .joinToString(" ")
                    result.success(deviceName.ifEmpty { "POS Device" })
                }
                else -> result.notImplemented()
            }
        }
    }
}
