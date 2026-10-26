package com.oneshoot.charger_guard

import android.Manifest
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null

    private fun send(action: String, fg: Boolean) {
        val i = Intent(this, GuardService::class.java).setAction(action)
        if (fg && Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
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
                            "charging" to plugged
                        ))
                    }
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
