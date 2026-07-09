package com.example.healthtrack_clean

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val SECURITY_CHANNEL = "com.healthtrack.app/security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableSecureFlag" -> {
                    // Blocks screenshots, screen recording, and hides content in app switcher
                    runOnUiThread {
                        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                }
                "disableSecureFlag" -> {
                    runOnUiThread {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(true)
                }
                "isDeviceRooted" -> {
                    result.success(checkRootIndicators())
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createHealthTrackChannels()
        }
    }

    /** Basic root detection — checks for common root indicators (not foolproof but useful) */
    private fun checkRootIndicators(): Boolean {
        val rootPaths = arrayOf(
            "/system/app/Superuser.apk", "/sbin/su", "/system/bin/su",
            "/system/xbin/su", "/data/local/xbin/su", "/data/local/bin/su",
            "/system/sd/xbin/su", "/system/bin/failsafe/su", "/data/local/su",
            "/su/bin/su"
        )
        for (path in rootPaths) {
            if (File(path).exists()) return true
        }
        val buildTags = Build.TAGS
        if (buildTags != null && buildTags.contains("test-keys")) return true
        return false
    }

    private fun createHealthTrackChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val sounds = listOf("health_alert", "water_drop", "medicine", "gentle", "urgent")

        for (soundName in sounds) {
            val channelId = "health_tracker_channel_$soundName"
            if (nm.getNotificationChannel(channelId) != null) continue

            val soundUri = Uri.parse("android.resource://${packageName}/raw/$soundName")
            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .build()

            val channel = NotificationChannel(channelId, "HealthTrack ($soundName)", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Health reminders and alerts with $soundName sound"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 300, 150, 300)
                setSound(soundUri, audioAttributes)
                enableLights(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(channel)
        }

        if (nm.getNotificationChannel("health_tracker_channel") == null) {
            val defaultChannel = NotificationChannel("health_tracker_channel", "HealthTrack Alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Health reminders and alerts"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 300, 150, 300)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(defaultChannel)
        }
    }
}