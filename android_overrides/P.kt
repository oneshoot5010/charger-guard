package com.oneshoot.charger_guard

import android.content.Context
import android.content.SharedPreferences
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class CrashH(private val app: Context, private val old: Thread.UncaughtExceptionHandler?) : Thread.UncaughtExceptionHandler {
    override fun uncaughtException(t: Thread, e: Throwable) {
        P.logEx(app, "CRASH(" + t.name + ")", e)
        old?.uncaughtException(t, e)
    }
}

object P {
    fun sp(c: Context): SharedPreferences = c.getSharedPreferences("cg", Context.MODE_PRIVATE)
    fun i(c: Context, k: String, d: Int): Int = sp(c).getInt(k, d)

    fun lastKnown(c: Context): Location? {
        val lm = c.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        var best: Location? = null
        for (p in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER)) {
            try {
                val l = lm.getLastKnownLocation(p)
                if (l != null && (best == null || l.time > best.time)) best = l
            } catch (e: Exception) {
            }
        }
        return best
    }

    @Suppress("DEPRECATION")
    fun verCode(c: Context): Long {
        val pi = c.packageManager.getPackageInfo(c.packageName, 0)
        return if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode else pi.versionCode.toLong()
    }

    fun verName(c: Context): String =
        c.packageManager.getPackageInfo(c.packageName, 0).versionName ?: ""

    fun log(c: Context, msg: String) {
        try {
            val f = File(c.filesDir, "errors.log")
            if (f.exists() && f.length() > 100000) f.writeText(f.readText().takeLast(50000))
            val ts = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
            f.appendText("[" + ts + "] " + msg + "\n")
        } catch (e: Exception) {
        }
    }

    fun logEx(c: Context, tag: String, e: Throwable) {
        log(c, tag + ": " + Log.getStackTraceString(e))
    }

    fun installCrashLogger(c: Context) {
        val old = Thread.getDefaultUncaughtExceptionHandler()
        if (old is CrashH) return
        Thread.setDefaultUncaughtExceptionHandler(CrashH(c.applicationContext, old))
    }
}
