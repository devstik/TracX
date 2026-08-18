package com.example.tracx

import android.app.AlarmManager
import android.app.Notification
import android.app.Notification.Builder
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.graphics.Typeface
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

class StockMonitorService : Service() {
    private var scheduler: ScheduledExecutorService? = null
    private var lastSummary: StockSummary? = null
    private var stoppedByUser = false
    private val apiDateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    private val timeFormat = SimpleDateFormat("HH:mm", Locale("pt", "BR"))
    private val numberFormat = DecimalFormat(
        "#,##0.##",
        DecimalFormatSymbols(Locale("pt", "BR"))
    )

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stoppedByUser = true
            cancelNextAlarm()
            stopSelf()
            return START_NOT_STICKY
        }
        stoppedByUser = false

        if (scheduler == null) {
            startForeground(NOTIFICATION_ID, buildLoadingNotification())
            startMonitoring()
        } else if (intent?.action == ACTION_REFRESH) {
            scheduler?.execute { updateStockNotification() }
        }
        scheduleNextAlarm()
        return START_STICKY
    }

    override fun onDestroy() {
        scheduler?.shutdownNow()
        scheduler = null
        if (!stoppedByUser) scheduleNextAlarm()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startMonitoring() {
        if (scheduler != null) return
        scheduler = Executors.newSingleThreadScheduledExecutor().also { executor ->
            executor.execute { updateStockNotification() }
            executor.scheduleWithFixedDelay(
                { updateStockNotification() },
                UPDATE_INTERVAL_SECONDS,
                UPDATE_INTERVAL_SECONDS,
                TimeUnit.SECONDS
            )
        }
    }

    private fun updateStockNotification() {
        val wakeLock = createWakeLock()
        val manager = getSystemService(NotificationManager::class.java)
        try {
            wakeLock?.acquire(60_000L)
            val summary = fetchTodaySummary()
            val total = numberFormat.format(summary.total)
            val updatedAt = timeFormat.format(Date())
            rememberSummary(summary)
            manager.notify(
                NOTIFICATION_ID,
                buildStockNotification(
                    total = total,
                    articles = summary.articles,
                    updatedAt = updatedAt
                )
            )
        } catch (error: Exception) {
            val updatedAt = timeFormat.format(Date())
            manager.notify(NOTIFICATION_ID, buildErrorNotification(updatedAt))
        } finally {
            if (wakeLock?.isHeld == true) wakeLock.release()
            scheduleNextAlarm()
        }
    }

    private fun createWakeLock(): PowerManager.WakeLock? {
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return null
        return powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$packageName:StockMonitorUpdate"
        ).apply {
            setReferenceCounted(false)
        }
    }

    private fun scheduleNextAlarm() {
        val alarmManager = getSystemService(AlarmManager::class.java) ?: return
        val triggerAt = android.os.SystemClock.elapsedRealtime() + UPDATE_INTERVAL_MILLIS
        val pendingIntent = buildRefreshPendingIntent(this)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerAt,
                pendingIntent
            )
        } else {
            alarmManager.set(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerAt,
                pendingIntent
            )
        }
    }

    private fun cancelNextAlarm() {
        val alarmManager = getSystemService(AlarmManager::class.java) ?: return
        alarmManager.cancel(buildRefreshPendingIntent(this))
    }

    private fun fetchTodaySummary(): StockSummary {
        val today = apiDateFormat.format(Date())
        val url = URL(
            "$BASE_URL/consultar/movimentacao-estoque?dataInicial=$today&dataFinal=$today&resumo=1"
        )
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 12000
            readTimeout = 20000
            setRequestProperty("Accept", "application/json")
        }

        return try {
            val status = connection.responseCode
            val stream = if (status in 200..299) {
                connection.inputStream
            } else {
                connection.errorStream
            }
            val body = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            if (status !in 200..299) {
                throw IllegalStateException("HTTP $status")
            }

            parseStockSummary(body)
        } finally {
            connection.disconnect()
        }
    }

    private fun parseStockSummary(body: String): StockSummary {
        val items = when {
            body.trim().startsWith("[") -> JSONArray(body)
            else -> {
                val root = JSONObject(body)
                if (root.has("total") || root.has("artigos")) {
                    return StockSummary(
                        total = toDouble(root.opt("total")),
                        articles = toInt(root.opt("artigos"))
                    )
                }
                when (val data = root.opt("data") ?: root.opt("resultados")) {
                    is JSONArray -> data
                    else -> JSONArray()
                }
            }
        }

        var total = 0.0
        var articles = 0

        for (index in 0 until items.length()) {
            val item = items.optJSONObject(index) ?: continue
            val level = toInt(item.opt("Nivel"))
            if (level == 1) {
                total += toDouble(item.opt("QtEntrada"))
            } else if (level == 2) {
                articles += 1
            }
        }

        return StockSummary(total, articles)
    }

    private fun rememberSummary(summary: StockSummary) {
        lastSummary = summary
    }

    private fun buildLoadingNotification(): Notification {
        return buildBaseNotification()
            .setContentTitle("TracX - Estoque")
            .setContentText("Consultando entrada de estoque...")
            .setSubText("Tempo real")
            .setStyle(
                Notification.BigTextStyle()
                    .setBigContentTitle("TracX - Estoque em tempo real")
                    .bigText("Consultando a entrada de estoque do dia atual.")
            )
            .setProgress(0, 0, true)
            .build()
    }

    private fun buildStockNotification(
        total: String,
        articles: Int,
        updatedAt: String
    ): Notification {
        return buildBaseNotification()
            .setContentTitle("Entrada de estoque hoje")
            .setContentText("Total: $total | $articles artigos")
            .setSubText("Atualizado $updatedAt")
            .setOnlyAlertOnce(true)
            .setTicker(null)
            .setStyle(
                Notification.InboxStyle()
                    .setBigContentTitle("TracX - Estoque em tempo real")
                    .setSummaryText("Atualizado às $updatedAt")
                    .addLine(strongLine("Total de entrada", total))
                    .addLine(strongLine("Artigos movimentados", articles.toString()))
                    .addLine("Próxima atualização em até 15 segundos")
            )
            .build()
    }

    private fun buildErrorNotification(updatedAt: String): Notification {
        return buildBaseNotification()
            .setContentTitle("Estoque não atualizado")
            .setContentText("Tentando novamente em até 15 segundos")
            .setSubText(updatedAt)
            .setStyle(
                Notification.BigTextStyle()
                    .setBigContentTitle("TracX - Estoque")
                    .bigText(
                        "Não foi possível atualizar a entrada de estoque às $updatedAt. " +
                            "O monitor continuará tentando automaticamente."
                    )
            )
            .build()
    }

    private fun buildBaseNotification(): Builder {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        val pendingOpenIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, StockMonitorService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Builder(this)
        }

        @Suppress("DEPRECATION")
        builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Parar", stopIntent)

        return builder
            .setSmallIcon(R.drawable.ic_stock_notification)
            .setContentIntent(pendingOpenIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setPriority(Notification.PRIORITY_DEFAULT)
            .setCategory(Notification.CATEGORY_STATUS)
            .setColor(0xFF16A34A.toInt())
    }

    private fun strongLine(label: String, value: String): SpannableString {
        val text = "$label: $value"
        return SpannableString(text).apply {
            setSpan(
                StyleSpan(Typeface.BOLD),
                0,
                label.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            setSpan(
                ForegroundColorSpan(0xFF16A34A.toInt()),
                label.length + 2,
                text.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Estoque em tempo real",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Mostra a entrada de estoque do dia atual na tela bloqueada sem alertas repetidos."
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(true)
            enableVibration(false)
            setSound(null, null)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun toInt(value: Any?): Int {
        return when (value) {
            is Number -> value.toInt()
            is String -> value.trim().toIntOrNull() ?: 0
            else -> 0
        }
    }

    private fun toDouble(value: Any?): Double {
        return when (value) {
            is Number -> value.toDouble()
            is String -> {
                var normalized = value.trim().replace(Regex("\\s+"), "")
                normalized = if (normalized.contains(",") && normalized.contains(".")) {
                    normalized.replace(".", "").replace(",", ".")
                } else {
                    normalized.replace(",", ".")
                }
                normalized.toDoubleOrNull() ?: 0.0
            }
            else -> 0.0
        }
    }

    private data class StockSummary(val total: Double, val articles: Int)

    companion object {
        const val ACTION_STOP = "com.example.tracx.STOP_STOCK_MONITOR"
        const val ACTION_REFRESH = "com.example.tracx.REFRESH_STOCK_MONITOR"
        const val CHANNEL_ID = "tracx_stock_monitor_lockscreen_v4"
        const val NOTIFICATION_ID = 3205
        const val BASE_URL = "http://168.190.90.2:5000"
        const val UPDATE_INTERVAL_SECONDS = 15L
        val UPDATE_INTERVAL_MILLIS: Long = TimeUnit.SECONDS.toMillis(UPDATE_INTERVAL_SECONDS)

        fun start(context: Context, action: String? = null) {
            val intent = Intent(context, StockMonitorService::class.java).apply {
                if (action != null) setAction(action)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, StockMonitorService::class.java))
        }

        fun buildRefreshPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, StockMonitorReceiver::class.java).setAction(ACTION_REFRESH)
            return PendingIntent.getBroadcast(
                context,
                2,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }
}

