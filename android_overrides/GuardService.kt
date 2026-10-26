package com.oneshoot.charger_guard

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

class GuardService : Service() {
    companion object {
        const val A_START = "cg.START"
        const val A_TOOK = "cg.TOOK"
        const val A_TEST = "cg.TEST"

        @Volatile var state = "off" // off, idle, tracking, alarm
        @Volatile var dist = 0f
        @Volatile var limit = 10f
        @Volatile var away = false
        @Volatile var steps = 0
        @Volatile var plugged = false
    }

    private lateinit var lm: LocationManager
    private val handler = Handler(Looper.getMainLooper())
    private var anchor: Location? = null
    private var trackStart = 0L
    private var player: MediaPlayer? = null
    private var receiverOn = false
    private var fgOn = false
    private var gpsDist = 0f

    private val timeoutRun = Runnable {
        if (state == "tracking") { stopTracking(); state = "idle"; refresh() }
    }
    private val alarmCap = Runnable {
        if (state == "alarm") { stopAlarm(); stopTracking(); state = "idle"; refresh() }
    }

    private val powerReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            when (i.action) {
                Intent.ACTION_POWER_DISCONNECTED -> onDisconnected()
                Intent.ACTION_POWER_CONNECTED -> onConnected()
            }
        }
    }

    private val locListener = object : LocationListener {
        override fun onLocationChanged(location: Location) { onFix(location) }
        @Deprecated("old api")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
    }

    private val stepListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            steps += 1
            updateDist()
        }
        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        P.installCrashLogger(this)
        lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(NotificationChannel("status", "حالة الحارس", NotificationManager.IMPORTANCE_LOW))
            val ch = NotificationChannel("alarm", "إنذار الشاحن", NotificationManager.IMPORTANCE_HIGH)
            ch.setSound(null, null)
            ch.enableVibration(false)
            nm.createNotificationChannel(ch)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            when (intent?.action) {
                A_TOOK -> {
                    stopAlarm(); stopTracking()
                    if (!receiverOn) shutdown() else { state = "idle"; refresh() }
                }
                A_TEST -> { goForeground(); fireAlarm(false) }
                else -> {
                    plugged = isPlugged()
                    goForeground(); registerPower()
                    state = "idle"; refresh()
                }
            }
        } catch (e: Exception) {
            P.logEx(this, "service", e)
            shutdown()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopAlarm(); stopTracking()
        if (receiverOn) { try { unregisterReceiver(powerReceiver) } catch (e: Exception) {} ; receiverOn = false }
        state = "off"
        super.onDestroy()
    }

    private fun shutdown() {
        stopForeground(true)
        stopSelf()
    }

    // ---------- notifications ----------
    private fun nb(ch: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, ch) else Notification.Builder(this)

    private fun act(a: String): PendingIntent = PendingIntent.getService(
        this, 1, Intent(this, GuardService::class.java).setAction(a),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun openApp(): PendingIntent {
        val i = packageManager.getLaunchIntentForPackage(packageName) ?: Intent()
        return PendingIntent.getActivity(this, 0, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun statusNotif(title: String, text: String): Notification {
        val b = nb("status").setSmallIcon(R.drawable.ic_stat).setContentTitle(title)
            .setContentText(text).setOngoing(true).setContentIntent(openApp())
        if (state == "tracking" || state == "alarm") b.addAction(0, "خدت الشاحن ✅", act(A_TOOK))
        return b.build()
    }

    private fun alarmNotif(): Notification {
        val b = nb("alarm").setSmallIcon(R.drawable.ic_stat).setContentTitle("⚠️ نسيت الشاحن!")
            .setContentText("اضغط «خدت الشاحن» لإيقاف الإنذار").setOngoing(true)
            .setContentIntent(openApp()).addAction(0, "خدت الشاحن ✅", act(A_TOOK))
        if (Build.VERSION.SDK_INT < 26) b.setPriority(Notification.PRIORITY_HIGH)
        return b.build()
    }

    private fun isPlugged(): Boolean {
        val b = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        return (b?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
    }

    private fun texts(): Pair<String, String> = when (state) {
        "tracking" -> "فصلت الشاحن" to "بتابع مكانك… لو بعدت هرن عليك"
        "alarm" -> "نسيت الشاحن!" to "اضغط «خدت الشاحن» لإيقاف الإنذار"
        else -> "الحارس شغّال" to (if (plugged) "الشاحن موصّل — بستنى فصله" else "الشاحن مفصول — وصّله عشان أبدأ المراقبة")
    }

    private fun refresh() {
        val (t, x) = texts()
        getSystemService(NotificationManager::class.java).notify(1, statusNotif(t, x))
    }

    private fun goForeground() {
        if (fgOn) return
        val n = statusNotif(texts().first, texts().second)
        if (Build.VERSION.SDK_INT >= 29) startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        else startForeground(1, n)
        fgOn = true
    }

    // ---------- power events ----------
    private fun registerPower() {
        if (receiverOn) return
        val f = IntentFilter()
        f.addAction(Intent.ACTION_POWER_CONNECTED)
        f.addAction(Intent.ACTION_POWER_DISCONNECTED)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(powerReceiver, f, Context.RECEIVER_EXPORTED)
        else registerReceiver(powerReceiver, f)
        receiverOn = true
    }

    private fun onConnected() {
        plugged = true
        if (state == "idle") refresh()
        if (state == "tracking" || state == "alarm") {
            stopAlarm(); stopTracking(); state = "idle"; refresh()
        }
    }

    private fun onDisconnected() {
        plugged = false
        if (state == "alarm") return
        stopTracking()
        steps = 0
        gpsDist = 0f
        away = false
        limit = P.i(this, "threshold", 10).toFloat()
        val lk = P.lastKnown(this)
        if (lk != null && System.currentTimeMillis() - lk.time < 120000L) setAnchor(lk) else anchor = null
        trackStart = System.currentTimeMillis()
        state = "tracking"
        startUpdates()
        refresh()
        handler.postDelayed(timeoutRun, P.i(this, "monitor", 30) * 60000L)
    }

    // ---------- location ----------
    private fun setAnchor(l: Location) {
        anchor = l
        away = false
        val sp = P.sp(this)
        val hl = sp.getString("home_lat", null)
        val ho = sp.getString("home_lon", null)
        if (hl != null && ho != null) {
            val h = Location("home")
            h.latitude = hl.toDouble()
            h.longitude = ho.toDouble()
            away = l.distanceTo(h) > 300f
        }
        val th = P.i(this, "threshold", 10)
        limit = if (away) maxOf(1, th / 2).toFloat() else th.toFloat()
    }

    private fun startUpdates() {
        try {
            if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER))
                lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 2000L, 0f, locListener)
            if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER))
                lm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 3000L, 0f, locListener)
        } catch (e: Exception) {
            P.logEx(this, "location", e)
        }
        try {
            val ok = Build.VERSION.SDK_INT < 29 ||
                checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED
            val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
            val st = sm.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
            if (ok && st != null) sm.registerListener(stepListener, st, SensorManager.SENSOR_DELAY_NORMAL)
        } catch (e: Exception) {
            P.logEx(this, "steps", e)
        }
    }

    private fun onFix(l: Location) {
        if (l.hasAccuracy() && l.accuracy > 50f) return
        val a = anchor
        if (a == null) { setAnchor(l); return }
        if (System.currentTimeMillis() - trackStart < 15000L && l.hasAccuracy() && a.hasAccuracy() && l.accuracy < a.accuracy) {
            setAnchor(l); return
        }
        val noise = ((if (a.hasAccuracy()) a.accuracy else 0f) + (if (l.hasAccuracy()) l.accuracy else 0f)) / 2f
        gpsDist = maxOf(0f, a.distanceTo(l) - noise)
        updateDist()
    }

    private fun updateDist() {
        dist = maxOf(gpsDist, steps * 0.7f)
        if (state == "tracking" && dist > limit) fireAlarm(true)
    }

    private fun stopTracking() {
        handler.removeCallbacks(timeoutRun)
        try { lm.removeUpdates(locListener) } catch (e: Exception) {}
        try { (getSystemService(Context.SENSOR_SERVICE) as SensorManager).unregisterListener(stepListener) } catch (e: Exception) {}
        anchor = null
        gpsDist = 0f
        steps = 0
        dist = 0f
    }

    // ---------- alarm ----------
    private fun inSilent(): Boolean {
        if (!P.sp(this).getBoolean("silent_on", false)) return false
        val c = Calendar.getInstance()
        val now = c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
        val s = P.i(this, "silent_start", 1380)
        val e = P.i(this, "silent_end", 420)
        return if (s <= e) now >= s && now < e else (now >= s || now < e)
    }

    private fun fireAlarm(real: Boolean) {
        state = "alarm"
        refresh()
        if (real) addHistory()
        startSound()
        getSystemService(NotificationManager::class.java).notify(2, alarmNotif())
        handler.postDelayed(alarmCap, 600000L)
    }

    private fun startSound() {
        try {
            val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            val pat = longArrayOf(0, 800, 400)
            if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createWaveform(pat, 0)) else v.vibrate(pat, 0)
        } catch (e: Exception) { P.logEx(this, "vibrate", e) }
        if (inSilent()) return
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            val vol = if (away) max else maxOf(1, (max * 0.8).toInt())
            try { am.setStreamVolume(AudioManager.STREAM_ALARM, vol, 0) } catch (e: Exception) {}
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            val mp = MediaPlayer()
            mp.setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            mp.setDataSource(this, uri)
            mp.isLooping = true
            mp.prepare()
            mp.start()
            player = mp
        } catch (e: Exception) { P.logEx(this, "sound", e) }
    }

    private fun stopAlarm() {
        handler.removeCallbacks(alarmCap)
        try { player?.stop(); player?.release() } catch (e: Exception) {}
        player = null
        try { (getSystemService(Context.VIBRATOR_SERVICE) as Vibrator).cancel() } catch (e: Exception) {}
        try { getSystemService(NotificationManager::class.java).cancel(2) } catch (e: Exception) {}
    }

    private fun addHistory() {
        val sp = P.sp(this)
        val old = try { JSONArray(sp.getString("history", "[]")) } catch (e: Exception) { JSONArray() }
        val out = JSONArray()
        out.put(JSONObject().put("t", System.currentTimeMillis()).put("away", away).put("d", dist.toInt()))
        for (i in 0 until minOf(old.length(), 99)) out.put(old.get(i))
        sp.edit().putString("history", out.toString()).apply()
    }
}
