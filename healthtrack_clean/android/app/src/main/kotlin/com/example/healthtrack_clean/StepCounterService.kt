package com.example.healthtrack_clean

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import io.flutter.plugin.common.EventChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class StepCounterService : Service(), SensorEventListener {

    companion object {
        const val ACTION_START = "ACTION_START_STEP_TRACKING"
        const val ACTION_STOP = "ACTION_STOP_STEP_TRACKING"

        const val CHANNEL_ID = "step_tracking_channel"
        const val CHANNEL_NAME = "Step Tracking"
        const val NOTIFICATION_ID = 1011

        const val PREFS_NAME = "step_tracking_prefs"
        const val KEY_IS_TRACKING = "is_tracking"
        const val KEY_CURRENT_STEPS = "current_steps"
        const val KEY_BASE_SENSOR_VALUE = "base_sensor_value"
        const val KEY_LAST_SENSOR_VALUE = "last_sensor_value"
        const val KEY_LAST_DATE = "last_date"

        @Volatile
        var eventSink: EventChannel.EventSink? = null

        fun startService(context: Context) {
            val intent = Intent(context, StepCounterService::class.java).apply {
                action = ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            val intent = Intent(context, StepCounterService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }

        private fun prefs(context: Context): SharedPreferences {
            return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }

        fun isTracking(context: Context): Boolean {
            return prefs(context).getBoolean(KEY_IS_TRACKING, false)
        }

        fun getCurrentSteps(context: Context): Int {
            resetIfNewDay(context)
            return prefs(context).getInt(KEY_CURRENT_STEPS, 0)
        }

        private fun currentDate(): String {
            return SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
        }

        fun resetIfNewDay(context: Context) {
            val pref = prefs(context)
            val today = currentDate()
            val savedDate = pref.getString(KEY_LAST_DATE, null)

            if (savedDate == null) {
                pref.edit().putString(KEY_LAST_DATE, today).apply()
                return
            }

            if (savedDate != today) {
                val lastSensorValue = pref.getFloat(KEY_LAST_SENSOR_VALUE, -1f)
                pref.edit()
                    .putString(KEY_LAST_DATE, today)
                    .putInt(KEY_CURRENT_STEPS, 0)
                    .putFloat(KEY_BASE_SENSOR_VALUE, lastSensorValue)
                    .apply()
            }
        }

        fun emitStepUpdate(stepCount: Int, isTracking: Boolean) {
            eventSink?.success(
                mapOf(
                    "steps" to stepCount,
                    "isTracking" to isTracking
                )
            )
        }
    }

    private lateinit var sensorManager: SensorManager
    private var stepCounterSensor: Sensor? = null
    private lateinit var sharedPrefs: SharedPreferences

    override fun onCreate() {
        super.onCreate()
        sharedPrefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        stepCounterSensor = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        createNotificationChannel()
        resetIfNewDay(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopTracking()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                startTracking()
                return START_STICKY
            }
            else -> {
                if (isTracking(this)) {
                    startTracking()
                    return START_STICKY
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun startTracking() {
        val sensor = stepCounterSensor ?: run {
            stopSelf()
            return
        }

        resetIfNewDay(this)

        val notification = buildNotification(getCurrentSteps(this))

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceCompat.startForeground(
                    this,
                    NOTIFICATION_ID,
                    notification,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
                    } else {
                        0
                    }
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            stopSelf()
            return
        }

        sharedPrefs.edit().putBoolean(KEY_IS_TRACKING, true).apply()

        sensorManager.unregisterListener(this)
        sensorManager.registerListener(
            this,
            sensor,
            SensorManager.SENSOR_DELAY_UI
        )

        emitStepUpdate(getCurrentSteps(this), true)
    }

    private fun stopTracking() {
        sensorManager.unregisterListener(this)
        sharedPrefs.edit().putBoolean(KEY_IS_TRACKING, false).apply()
        emitStepUpdate(getCurrentSteps(this), false)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null || event.sensor.type != Sensor.TYPE_STEP_COUNTER) return

        resetIfNewDay(this)

        val totalSinceBoot = event.values.firstOrNull() ?: return
        val baseSensorValue = sharedPrefs.getFloat(KEY_BASE_SENSOR_VALUE, -1f)

        if (baseSensorValue < 0f) {
            sharedPrefs.edit()
                .putFloat(KEY_BASE_SENSOR_VALUE, totalSinceBoot)
                .putFloat(KEY_LAST_SENSOR_VALUE, totalSinceBoot)
                .putInt(KEY_CURRENT_STEPS, 0)
                .putString(KEY_LAST_DATE, SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date()))
                .apply()

            updateNotification(0)
            emitStepUpdate(0, true)
            return
        }

        val todaySteps = (totalSinceBoot - baseSensorValue).toInt().coerceAtLeast(0)

        sharedPrefs.edit()
            .putFloat(KEY_LAST_SENSOR_VALUE, totalSinceBoot)
            .putInt(KEY_CURRENT_STEPS, todaySteps)
            .putString(KEY_LAST_DATE, SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date()))
            .apply()

        updateNotification(todaySteps)
        emitStepUpdate(todaySteps, true)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun onDestroy() {
        sensorManager.unregisterListener(this)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(steps: Int): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("👣 Health Tracker")
            .setContentText("Tracking Steps • Today's Steps: $steps")
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText("Tracking Steps\nToday's Steps: $steps")
            )
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun updateNotification(steps: Int) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(steps))
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows ongoing step tracking"
                setShowBadge(false)
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun immutableFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
    }
}