package com.example.tracx

import android.Manifest
import android.app.ActivityManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.tracx/datawedge"
    private val BLUETOOTH_CHANNEL = "com.example.tracx/bluetooth_printer"
    private val STOCK_MONITOR_CHANNEL = "com.example.tracx/stock_monitor"
    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private var methodChannel: MethodChannel? = null
    private var bluetoothChannel: MethodChannel? = null
    private var stockMonitorChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        // Métodos Flutter -> Android
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

        bluetoothChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BLUETOOTH_CHANNEL
        )

        bluetoothChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "listDevices" -> listBluetoothDevices(result)
                "print" -> {
                    val address = call.argument<String>("address")
                    val payload = call.argument<String>("payload")
                    printBluetooth(address, payload, result)
                }
                else -> result.notImplemented()
            }
        }

        stockMonitorChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STOCK_MONITOR_CHANNEL
        )

        stockMonitorChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    StockMonitorService.start(this)
                    result.success(true)
                }
                "stop" -> {
                    StockMonitorService.stop(this)
                    result.success(true)
                }
                "isRunning" -> result.success(isStockMonitorRunning())
                else -> result.notImplemented()
            }
        }
    }

    private fun isStockMonitorRunning(): Boolean {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        @Suppress("DEPRECATION")
        return manager.getRunningServices(Int.MAX_VALUE).any {
            it.service.className == StockMonitorService::class.java.name
        }
    }

    private fun bluetoothAdapter(): BluetoothAdapter? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val manager = getSystemService(BluetoothManager::class.java)
            manager?.adapter
        } else {
            @Suppress("DEPRECATION")
            BluetoothAdapter.getDefaultAdapter()
        }
    }

    private fun hasBluetoothPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED &&
                checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
        } else {
            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun deviceToMap(device: BluetoothDevice, bonded: Boolean): Map<String, Any?> {
        val name = try {
            if (hasBluetoothPermission()) device.name else null
        } catch (_: SecurityException) {
            null
        }

        return mapOf(
            "address" to device.address,
            "name" to (name ?: device.address),
            "bonded" to bonded
        )
    }

    private fun listBluetoothDevices(result: MethodChannel.Result) {
        if (!hasBluetoothPermission()) {
            result.error(
                "BLUETOOTH_PERMISSION",
                "Permissao de Bluetooth nao concedida.",
                null
            )
            return
        }

        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.error("BLUETOOTH_UNAVAILABLE", "Bluetooth nao disponivel neste aparelho.", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("BLUETOOTH_DISABLED", "Ative o Bluetooth do aparelho.", null)
            return
        }

        val devices = linkedMapOf<String, Map<String, Any?>>()
        try {
            adapter.bondedDevices?.forEach { device ->
                devices[device.address] = deviceToMap(device, true)
            }
        } catch (e: SecurityException) {
            result.error("BLUETOOTH_PERMISSION", e.message, null)
            return
        }

        val handler = Handler(Looper.getMainLooper())
        var finished = false

        lateinit var receiver: BroadcastReceiver
        fun finish() {
            if (finished) return
            finished = true
            try {
                unregisterReceiver(receiver)
            } catch (_: Exception) {
            }
            try {
                adapter.cancelDiscovery()
            } catch (_: SecurityException) {
            }
            result.success(devices.values.toList())
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val device: BluetoothDevice? =
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                intent.getParcelableExtra(
                                    BluetoothDevice.EXTRA_DEVICE,
                                    BluetoothDevice::class.java
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                            }
                        if (device != null) {
                            val bonded = device.bondState == BluetoothDevice.BOND_BONDED
                            devices[device.address] = deviceToMap(device, bonded)
                        }
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> finish()
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(receiver, filter)
        }

        try {
            adapter.cancelDiscovery()
            adapter.startDiscovery()
            handler.postDelayed({ finish() }, 9000)
        } catch (e: SecurityException) {
            finish()
        }
    }

    private fun printBluetooth(
        address: String?,
        payload: String?,
        result: MethodChannel.Result
    ) {
        if (address.isNullOrBlank() || payload.isNullOrEmpty()) {
            result.error("BLUETOOTH_INVALID_ARGS", "Dispositivo ou etiqueta nao informado.", null)
            return
        }
        if (!hasBluetoothPermission()) {
            result.error("BLUETOOTH_PERMISSION", "Permissao de Bluetooth nao concedida.", null)
            return
        }

        val adapter = bluetoothAdapter()
        if (adapter == null || !adapter.isEnabled) {
            result.error("BLUETOOTH_DISABLED", "Ative o Bluetooth do aparelho.", null)
            return
        }

        Thread {
            try {
                adapter.cancelDiscovery()
                val device = adapter.getRemoteDevice(address)
                if (device.bondState == BluetoothDevice.BOND_NONE) {
                    device.createBond()
                    val start = System.currentTimeMillis()
                    while (device.bondState != BluetoothDevice.BOND_BONDED &&
                        System.currentTimeMillis() - start < 30000
                    ) {
                        Thread.sleep(500)
                    }
                }

                val socket = try {
                    device.createRfcommSocketToServiceRecord(SPP_UUID)
                } catch (e: IOException) {
                    device.createInsecureRfcommSocketToServiceRecord(SPP_UUID)
                }
                socket.connect()
                val bytes = payload.toByteArray(Charsets.UTF_8)
                socket.outputStream.use { stream ->
                    var offset = 0
                    val chunkSize = 4096
                    while (offset < bytes.size) {
                        val length = minOf(chunkSize, bytes.size - offset)
                        stream.write(bytes, offset, length)
                        offset += length
                        Thread.sleep(2)
                    }
                    stream.flush()
                    Thread.sleep(250)
                }
                socket.close()
                runOnUiThread { result.success(null) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error(
                        "BLUETOOTH_PRINT_ERROR",
                        "Falha ao imprimir via Bluetooth. ${e.message}",
                        null
                    )
                }
            }
        }.start()
    }

    override fun onResume() {
        super.onResume()
        registerReceiver(
            dataWedgeReceiver,
            IntentFilter("com.example.tracx.SCAN"),
            Context.RECEIVER_NOT_EXPORTED
        )
    }

    override fun onPause() {
        unregisterReceiver(dataWedgeReceiver)
        super.onPause()
    }

    private fun configureDataWedgeProfile(
        profileName: String?,
        intentAction: String?
    ) {
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

        val intent = Intent("com.symbol.datawedge.api.SET_CONFIG").apply {
            putExtra("com.symbol.datawedge.api.SET_CONFIG", profileConfig)
        }

        sendBroadcast(intent)
    }

    private val dataWedgeReceiver: BroadcastReceiver =
        object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null) return

                val scannedData =
                    intent.getStringExtra("com.symbol.datawedge.data_string")

                if (scannedData != null) {
                    methodChannel?.invokeMethod(
                        "onScan",
                        mapOf("data" to scannedData)
                    )
                }
            }
        }
}
