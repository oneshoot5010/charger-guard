package com.oneshoot.charger_guard

import android.Manifest
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageInstaller
import android.location.LocationManager
import android.net.Uri
import java.io.File
import java.io.FileInputStream
import android.os.BatteryManager
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var autoStart = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        P.installCrashLogger(this)
        scheduleUpdateCheck()
        if (intent?.getBooleanExtra("autostart", false) == true) autoStart = true
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("autostart", false)) autoStart = true
    }

    override fun onResume() {
        super.onResume()
        if (autoStart) {
            autoStart = false
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                try { send(GuardService.A_START, true) } catch (e: Exception) {}
            }
        }
    }

    private fun send(action: String, fg: Boolean) {
        val i = Intent(this, GuardService::class.java).setAction(action)
        if (fg && Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
    }

    private fun scheduleUpdateCheck() {
        try {
            val js = getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
            if (js.allPendingJobs.any { it.id == 1001 }) return
            val job = JobInfo.Builder(1001, ComponentName(this, UpdateJob::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPeriodic(12L * 3600L * 1000L)
                .setPersisted(true)
                .build()
            js.schedule(job)
        } catch (e: Exception) {
            P.logEx(this, "schedule", e)
        }
    }

    private fun installApk(path: String) {
        val f = File(path)
        val pi = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        val id = pi.createSession(params)
        val session = pi.openSession(id)
        FileInputStream(f).use { ins ->
            session.openWrite("charger-guard", 0, f.length()).use { out ->
                ins.copyTo(out)
                session.fsync(out)
            }
        }
        val fl = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
        val pending = PendingIntent.getBroadcast(this, id, Intent(this, InstallReceiver::class.java), fl)
        session.commit(pending.intentSender)
        session.close()
    }

    private fun buildReport(): String {
        val sb = StringBuilder()
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        val lm = getSystemService(LOCATION_SERVICE) as LocationManager
        val sp = P.sp(this)
        fun gr(p: String) = checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED
        sb.append("== تقرير حارس الشاحن ==\n")
        sb.append("الإصدار: " + P.verName(this) + " (" + P.verCode(this) + ")\n")
        sb.append("أندرويد: " + Build.VERSION.RELEASE + " (SDK " + Build.VERSION.SDK_INT + ")\n")
        sb.append("الجهاز: " + Build.MANUFACTURER + " " + Build.MODEL + "\n")
        sb.append("حالة الحارس: " + GuardService.state + "\n")
        sb.append("استثناء البطارية: " + pm.isIgnoringBatteryOptimizations(packageName) + "\n")
        sb.append("إذن الموقع: " + gr(Manifest.permission.ACCESS_FINE_LOCATION) + "\n")
        sb.append("GPS شغال: " + lm.isProviderEnabled(LocationManager.GPS_PROVIDER) + "\n")
        sb.append("إذن الإشعارات: " + (Build.VERSION.SDK_INT < 33 || gr(Manifest.permission.POST_NOTIFICATIONS)) + "\n")
        sb.append("إذن النشاط البدني: " + (Build.VERSION.SDK_INT < 29 || gr(Manifest.permission.ACTIVITY_RECOGNITION)) + "\n")
        sb.append("المسافة: " + sp.getInt("threshold", 10) + " م | المراقبة: " + sp.getInt("monitor", 30) + " د\n")
        sb.append("\n== السجل ==\n")
        val f = File(filesDir, "errors.log")
        sb.append(if (f.exists() && f.length() > 0L) f.readText().takeLast(6000) else "مفيش أخطاء متسجلة ✓")
        return sb.toString()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cg").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "settings" -> {
                        val sp = P.sp(this)
                        result.success(hashMapOf<String, Any>(
                            "threshold" to sp.getInt("threshold", 10),
                            "monitor" to sp.getInt("monitor", 30),
                            "silent_on" to sp.getBoolean("silent_on", false),
                            "silent_start" to sp.getInt("silent_start", 1380),
                            "silent_end" to sp.getInt("silent_end", 420),
                            "theme" to (sp.getString("theme", "system") ?: "system"),
                            "home_set" to sp.contains("home_lat")
                        ))
                    }
                    "set" -> {
                        val k = call.argument<String>("k")!!
                        val v = call.argument<Any>("v")
                        val e = P.sp(this).edit()
                        when (v) {
                            is Boolean -> e.putBoolean(k, v)
                            is Int -> e.putInt(k, v)
                            is String -> e.putString(k, v)
                        }
                        e.apply()
                        result.success(true)
                    }
                    "perm" -> {
                        val need = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
                        if (Build.VERSION.SDK_INT >= 33) need.add(Manifest.permission.POST_NOTIFICATIONS)
                        if (Build.VERSION.SDK_INT >= 29) need.add(Manifest.permission.ACTIVITY_RECOGNITION)
                        val missing = need.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
                        if (missing.isEmpty()) {
                            result.success(true)
                        } else {
                            pending = result
                            requestPermissions(missing.toTypedArray(), 77)
                        }
                    }
                    "start" -> { send(GuardService.A_START, true); result.success(true) }
                    "stop" -> { stopService(Intent(this, GuardService::class.java)); GuardService.state = "off"; result.success(true) }
                    "took" -> { send(GuardService.A_TOOK, false); result.success(true) }
                    "test" -> { send(GuardService.A_TEST, true); result.success(true) }
                    "status" -> {
                        val b = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                        val plugged = (b?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
                        result.success(hashMapOf<String, Any>(
                            "state" to GuardService.state,
                            "dist" to GuardService.dist.toDouble(),
                            "limit" to GuardService.limit.toDouble(),
                            "away" to GuardService.away,
                            "steps" to GuardService.steps,
                            "charging" to plugged
                        ))
                    }
                    "batteryOk" -> {
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "batteryAsk" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
                        } catch (e: Exception) {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        }
                        result.success(true)
                    }
                    "updDir" -> {
                        val d = File(cacheDir, "updates")
                        d.mkdirs()
                        result.success(d.absolutePath)
                    }
                    "appVersion" -> result.success(hashMapOf<String, Any>("code" to P.verCode(this), "name" to P.verName(this)))
                    "install" -> {
                        val path = call.argument<String>("path")!!
                        Thread {
                            var ok = true
                            try {
                                installApk(path)
                            } catch (e: Exception) {
                                ok = false
                                P.logEx(this, "install", e)
                            }
                            runOnUiThread { result.success(ok) }
                        }.start()
                    }
                    "report" -> result.success(buildReport())
                    "clearLog" -> { File(filesDir, "errors.log").delete(); result.success(true) }
                    "log" -> { P.log(this, "Dart: " + (call.argument<String>("m") ?: "")); result.success(true) }
                    "history" -> result.success(P.sp(this).getString("history", "[]") ?: "[]")
                    "clearHistory" -> { P.sp(this).edit().remove("history").apply(); result.success(true) }
                    "home" -> {
                        val l = P.lastKnown(this)
                        if (l == null) {
                            result.success(false)
                        } else {
                            P.sp(this).edit()
                                .putString("home_lat", l.latitude.toString())
                                .putString("home_lon", l.longitude.toString())
                                .apply()
                            result.success(true)
                        }
                    }
                    "open" -> {
                        val url = call.argument<String>("url")!!
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                P.logEx(this, "channel:" + call.method, e)
                result.success(false)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 77) {
            val ok = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
            pending?.success(ok)
            pending = null
        }
    }
}
