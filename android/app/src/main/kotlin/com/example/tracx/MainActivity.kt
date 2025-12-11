package com.example.tracx

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.tracx/datawedge"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        // Handler de métodos Flutter -> Android
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "configureProfile" -> {
                    val profileName = call.argument<String>("profileName")
                    val intentAction = call.argument<String>("intentAction")
                    configureDataWedgeProfile(profileName, intentAction)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Receber scans do DataWedge
        registerReceiver(
            dataWedgeReceiver,
            IntentFilter("com.example.tracx.SCAN")
        )
    }

    private fun configureDataWedgeProfile(profileName: String?, intentAction: String?) {
        if (profileName == null || intentAction == null) return

        val profileConfig = Bundle().apply {
            putString("PROFILE_NAME", profileName)
            putBoolean("PROFILE_ENABLED", true)
            putString("CONFIG_MODE", "CREATE_IF_NOT_EXIST")
            putBundle("APP_LIST", Bundle().apply {
                putString("PACKAGE_NAME", packageName)
                putString("ACTIVITY_LIST", "*")
            })
            putBundle("INTENT_CONFIG", Bundle().apply {
                putBoolean("OUTPUT_ENABLED", true)
                putString("INTENT_ACTION", intentAction)
                putString("LABEL_TYPE", "NONE")
                putBoolean("START_ACTIVITY", false)
            })
        }

        val intent = Intent()
        intent.action = "com.symbol.datawedge.api.SET_CONFIG"
        intent.putExtra("com.symbol.datawedge.api.SET_CONFIG", profileConfig)
        sendBroadcast(intent)
    }

    private val dataWedgeReceiver: BroadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent == null) return

            val scannedData = intent.getStringExtra("com.symbol.datawedge.data_string")
            if (scannedData != null) {
                methodChannel?.invokeMethod("onScan", mapOf("data" to scannedData))
            }
        }
    }

    override fun onDestroy() {
        unregisterReceiver(dataWedgeReceiver)
        super.onDestroy()
    }
}
