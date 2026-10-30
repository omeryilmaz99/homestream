package com.homestream.homestream_files

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/** Shows "Aktarım sürüyor" while files are sent or received, so Android keeps the app alive. */
class TransferService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "Aktarım sürüyor"
        val text = intent?.getStringExtra("text") ?: ""
        val progress = intent?.getIntExtra("progress", -1) ?: -1
        val n = build(title, text, progress)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(ID, n)
        }
        setAwake(applicationContext, true)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        setAwake(applicationContext, false)
        super.onDestroy()
    }

    override fun onTimeout(startId: Int) {
        // Android 15 limits dataSync services to 6 h a day
        stopSelf()
    }

    private fun build(title: String, text: String, progress: Int): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Dosya aktarımları", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        @Suppress("DEPRECATION")
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        b.setSmallIcon(R.drawable.ic_stat_transfer)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
        if (progress in 0..100) b.setProgress(100, progress, false)
        return b.build()
    }

    companion object {
        private const val ID = 4210
        private const val CHANNEL = "transfers"
        private var wake: PowerManager.WakeLock? = null
        private var wifi: WifiManager.WifiLock? = null

        @Synchronized
        fun setAwake(ctx: Context, on: Boolean) {
            if (on) {
                if (wake == null) {
                    val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
                    wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "homedosya:transfer").apply {
                        setReferenceCounted(false)
                    }
                }
                if (wifi == null) {
                    val wm = ctx.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    @Suppress("DEPRECATION")
                    val mode = if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                        else WifiManager.WIFI_MODE_FULL_HIGH_PERF
                    wifi = wm.createWifiLock(mode, "homedosya:transfer").apply { setReferenceCounted(false) }
                }
                wake?.acquire(60 * 60 * 1000L)
                if (wifi?.isHeld == false) wifi?.acquire()
            } else {
                if (wake?.isHeld == true) wake?.release()
                if (wifi?.isHeld == true) wifi?.release()
            }
        }
    }
}
