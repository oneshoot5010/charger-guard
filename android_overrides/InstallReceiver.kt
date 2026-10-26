package com.oneshoot.charger_guard

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

class InstallReceiver : BroadcastReceiver() {
    @Suppress("DEPRECATION")
    override fun onReceive(c: Context, i: Intent) {
        val st = i.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)
        if (st == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            val conf: Intent? = if (Build.VERSION.SDK_INT >= 33)
                i.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            else
                i.getParcelableExtra(Intent.EXTRA_INTENT)
            if (conf != null) {
                conf.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try { c.startActivity(conf) } catch (e: Exception) { P.logEx(c, "install-prompt", e) }
            }
        } else if (st != PackageInstaller.STATUS_SUCCESS && st != -1) {
            P.log(c, "install status=" + st + " msg=" + i.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE))
        }
    }
}
