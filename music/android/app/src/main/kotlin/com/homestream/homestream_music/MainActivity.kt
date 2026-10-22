package com.homestream.homestream_music

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "homemusic/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // keep CPU and Wi-Fi awake while music streams with the screen off
                    "keepAwake" -> {
                        setAwake(applicationContext, call.argument<Boolean>("on") ?: false)
                        result.success(null)
                    }
                    "ignoringBatteryOptimizations" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            @Suppress("BatteryLife")
                            val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                            i.data = Uri.parse("package:$packageName")
                            startActivity(i)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    // back on the home screen: hide instead of closing (music keeps playing)
                    "moveToBack" -> result.success(moveTaskToBack(true))
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        private var wake: PowerManager.WakeLock? = null
        private var wifi: WifiManager.WifiLock? = null

        @Synchronized
        fun setAwake(ctx: Context, on: Boolean) {
            if (on) {
                if (wake == null) {
                    val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
                    wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "homemusic:playback").apply {
                        setReferenceCounted(false)
                    }
                }
                if (wifi == null) {
                    val wm = ctx.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    @Suppress("DEPRECATION")
                    val mode = if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                        else WifiManager.WIFI_MODE_FULL_HIGH_PERF
                    wifi = wm.createWifiLock(mode, "homemusic:stream").apply { setReferenceCounted(false) }
                }
                // re-acquired regularly by the app while playing; the timeout is a safety net
                wake?.acquire(30 * 60 * 1000L)
                if (wifi?.isHeld == false) wifi?.acquire()
            } else {
                if (wake?.isHeld == true) wake?.release()
                if (wifi?.isHeld == true) wifi?.release()
            }
        }
    }
}
