package com.example.healthtrack_clean

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "com.healthtrack/steps"
    private val eventChannelName = "com.healthtrack/steps_stream"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startTracking" -> {
                        if (!hasActivityRecognitionPermission()) {
                            result.error("PERMISSION_DENIED", "Activity recognition not granted", null)
                            return@setMethodCallHandler
                        }
                        StepCounterService.startService(this)
                        result.success(true)
                    }

                    "stopTracking" -> {
                        StepCounterService.stopService(this)
                        result.success(true)
                    }

                    "getCurrentSteps" -> {
                        result.success(StepCounterService.getCurrentSteps(this))
                    }

                    "isTracking" -> {
                        result.success(StepCounterService.isTracking(this))
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    StepCounterService.eventSink = events
                    StepCounterService.emitStepUpdate(
                        StepCounterService.getCurrentSteps(this@MainActivity),
                        StepCounterService.isTracking(this@MainActivity)
                    )
                }

                override fun onCancel(arguments: Any?) {
                    StepCounterService.eventSink = null
                }
            })
    }

    private fun hasActivityRecognitionPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACTIVITY_RECOGNITION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }
}