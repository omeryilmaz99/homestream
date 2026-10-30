package com.homestream.homestream_files

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "homedosya/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // a foreground service keeps transfers running with the screen off
                    "transfer" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        val i = Intent(applicationContext, TransferService::class.java)
                        if (on) {
                            i.putExtra("title", call.argument<String>("title") ?: "Aktarım sürüyor")
                            i.putExtra("text", call.argument<String>("text") ?: "")
                            i.putExtra("progress", call.argument<Int>("progress") ?: -1)
                            try {
                                if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
                            } catch (e: Exception) {
                                // not allowed from the background on new Android: the wake lock still helps
                                TransferService.setAwake(applicationContext, true)
                            }
                        } else {
                            stopService(i)
                            TransferService.setAwake(applicationContext, false)
                        }
                        result.success(null)
                    }
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "moveToBack" -> result.success(moveTaskToBack(true))
                    else -> result.notImplemented()
                }
            }
    }
}
