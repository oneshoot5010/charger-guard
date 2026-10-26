package com.oneshoot.charger_guard

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class GuardTile : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        refresh()
    }

    private fun refresh() {
        val t = qsTile ?: return
        t.state = if (GuardService.state != "off") Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        t.label = "حارس الشاحن"
        t.updateTile()
    }

    @Suppress("DEPRECATION")
    private fun openAndCollapse(i: Intent) {
        if (Build.VERSION.SDK_INT >= 34) {
            val pi = PendingIntent.getActivity(this, 5, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            startActivityAndCollapse(pi)
        } else {
            startActivityAndCollapse(i)
        }
    }

    override fun onClick() {
        super.onClick()
        if (GuardService.state != "off") {
            stopService(Intent(this, GuardService::class.java))
            GuardService.state = "off"
            refresh()
        } else {
            val i = Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra("autostart", true)
            openAndCollapse(i)
        }
    }
}
