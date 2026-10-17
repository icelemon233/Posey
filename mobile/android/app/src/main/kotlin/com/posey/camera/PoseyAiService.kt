package com.posey.camera

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class PoseyAiService : Service() {
    private val executor = Executors.newSingleThreadExecutor()
    private val working = AtomicBoolean(false)
    private lateinit var store: PoseyAiStore
    companion object {
        private const val channelId = "posey-ai-tasks"
        private const val ongoingId = 17204
        @Volatile var running = false
        fun start(context: Context,id:String?=null) {
            val intent = Intent(context, PoseyAiService::class.java)
            if(id!=null)intent.putExtra("activateJobId",id)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }
    }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() {
        super.onCreate(); running = true; store = PoseyAiStore.get(this)
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(channelId, "AI 任务", NotificationManager.IMPORTANCE_LOW))
        foreground("正在处理 AI 任务")
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val activation=intent?.getStringExtra("activateJobId")
        if(activation!=null&&PoseyAiStore.validId(activation)){
            try{store.activate(activation)}catch(_:Exception){store.safeUpdate(activation,"failed","任务记录未能保存，没有发送生成请求。")}
        }
        if (working.compareAndSet(false, true)) executor.execute {
            try {
                while (!store.pending()) {
                    val job = store.next() ?: break; val id = job.getString("id")
                    foreground("正在生成：${job.optString("targetTitle", "照片")}", id)
                    val wake = (getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Posey:AI")
                    try { wake.acquire(360_000); PoseyAiTransport.get(store).run(id) }
                    finally { if (wake.isHeld) wake.release() }
                    completed(id)
                }
            } finally {
                working.set(false)
                if (store.pending()) foreground("成片尚未留存，打开任务页处理")
                else if (store.next() != null) onStartCommand(null, 0, 0)
                else { if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
            }
        }
        return START_NOT_STICKY
    }
    private fun foreground(text: String, id: String? = null) {
        val notification = notification(text, id, true)
        if (Build.VERSION.SDK_INT >= 29) startForeground(ongoingId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else startForeground(ongoingId, notification)
    }
    private fun notification(text: String, id: String?, ongoing: Boolean): Notification {
        val open = Intent(this, MainActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP; if (id != null) putExtra("poseyJobId", id) }
        val pending = PendingIntent.getActivity(this, id?.hashCode() ?: ongoingId, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channelId) else Notification.Builder(this)
        builder.setSmallIcon(android.R.drawable.ic_menu_camera).setContentTitle("Posey").setContentText(text).setContentIntent(pending).setOngoing(ongoing).setAutoCancel(!ongoing)
        if (ongoing && id != null) {
            val cancel = Intent(this, PoseyAiCancelReceiver::class.java).putExtra("poseyJobId", id)
            val action = PendingIntent.getBroadcast(this, id.hashCode(), cancel, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            builder.addAction(Notification.Action.Builder(null, "取消生成", action).build())
        }
        return builder.build()
    }
    private fun completed(id: String) {
        val job = store.record(id) ?: return
        val text = when (job.optString("state")) { "completed" -> "生成完成，打开查看成片"; "awaitingResult" -> "成片尚未留存，打开任务页处理"; "cancelled" -> return; else -> "生成未完成，打开任务页查看" }
        try { getSystemService(NotificationManager::class.java).notify(id.hashCode(), notification(text, id, false)) } catch (_: SecurityException) { /* Denied notifications do not discard results. */ }
    }
    override fun onTimeout(startId: Int, fgsType: Int) {
        PoseyAiTransport.get(store).disconnectAll()
        store.records().filter { it.optString("state") == "generating" }.forEach { store.safeUpdate(it.getString("id"), "failed", "后台处理已中断，请核对服务记录后再决定重试。") }
        stopSelf()
    }
    override fun onDestroy() { running = false; executor.shutdown(); super.onDestroy() }
}
class PoseyAiCancelReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("poseyJobId") ?: return
        if (!PoseyAiStore.validId(id)) return
        val pending = goAsync()
        Thread {
            try { val store = PoseyAiStore.get(context); store.cancel(id); PoseyAiTransport.get(store).disconnect(id) }
            catch(_:Exception){android.os.Handler(android.os.Looper.getMainLooper()).post{android.widget.Toast.makeText(context,"取消未完成，请打开任务页重试。",android.widget.Toast.LENGTH_LONG).show()}}
            finally { pending.finish() }
        }.start()
    }
}
