package com.example.tracx

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class StockMonitorReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            StockMonitorService.ACTION_REFRESH,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED -> {
                StockMonitorService.start(context, StockMonitorService.ACTION_REFRESH)
            }
        }
    }
}
