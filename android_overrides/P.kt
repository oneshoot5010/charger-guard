package com.oneshoot.charger_guard

import android.content.Context
import android.content.SharedPreferences
import android.location.Location
import android.location.LocationManager

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
}
