package com.oneshoot.charger_guard

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobParameters
import android.app.job.JobService
import android.content.Intent
import android.os.Build
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class UpdateJob : JobService() {
    override fun onStartJob(params: JobParameters?): Boolean {
        Thread {
            try {
                check()
            } catch (e: Exception) {
                P.logEx(this, "updatejob", e)
            }
            jobFinished(params, false)
        }.start()
        return true
    }

    override fun onStopJob(params: JobParameters?): Boolean = false

    private fun check() {
        val c = URL("https://api.github.com/repos/oneshoot5010/charger-guard/releases/latest").openConnection() as HttpURLConnection
        c.connectTimeout = 15000
        c.readTimeout = 15000
        c.setRequestProperty("User-Agent", "charger-guard")
        c.setRequestProperty("Accept", "application/vnd.github+json")
        if (c.responseCode != 200) return
        val js = JSONObject(c.inputStream.bufferedReader().readText())
        val tag = js.optString("tag_name")
        val remote = tag.substringAfterLast('+', "").toIntOrNull() ?: return
        if (remote.toLong() <= P.verCode(this)) return
        val sp = P.sp(this)
        if (sp.getInt("notified_build", 0) >= remote) return
        notifyUpdate(tag.removePrefix("v").substringBefore('+'))
        sp.edit().putInt("notified_build", remote).apply()
    }

    private fun notifyUpdate(ver: String) {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel("update", "تحديثات التطبيق", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val li = packageManager.getLaunchIntentForPackage(packageName) ?: Intent()
        val pi = PendingIntent.getActivity(this, 3, li, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "update") else Notification.Builder(this)
        b.setSmallIcon(R.drawable.ic_stat)
            .setContentTitle("فيه تحديث جديد لحارس الشاحن")
            .setContentText("الإصدار " + ver + " — افتح التطبيق ثم الإعدادات ثم تحديث التطبيق")
            .setAutoCancel(true)
            .setContentIntent(pi)
        nm.notify(3, b.build())
    }
}
