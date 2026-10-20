package com.homestream.home_stream

import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "homestream/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTv" -> result.success(isTv())
                    "keepScreenOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        runOnUiThread {
                            if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "openExternal" -> {
                        val url = call.argument<String>("url") ?: ""
                        val title = call.argument<String>("title") ?: ""
                        val pkg = call.argument<String>("package")
                        val start = call.argument<Int>("startMs") ?: 0
                        val subs = call.argument<List<String>>("subtitles") ?: emptyList()
                        result.success(openExternal(url, title, pkg, start, subs))
                    }
                    "videoPlayers" -> result.success(videoPlayers())
                    else -> result.notImplemented()
                }
            }
    }

    private fun isTv(): Boolean {
        val ui = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
        if (ui.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) return true
        val pm = packageManager
        return pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            !pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
    }

    private fun videoIntent(url: String, title: String): Intent =
        Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse(url), "video/*")
            putExtra("title", title)
            putExtra(Intent.EXTRA_TITLE, title)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    private fun openExternal(
        url: String, title: String, pkg: String?, startMs: Int, subs: List<String>,
    ): Boolean {
        val intent = videoIntent(url, title)
        // resume position / subtitles, understood by VLC, MX Player and Just Player
        if (startMs > 1000) {
            intent.putExtra("position", startMs)
            intent.putExtra("from_start", false)
        }
        if (subs.isNotEmpty()) {
            intent.putExtra("subtitles_location", subs[0])
            intent.putExtra("subs", subs.map { Uri.parse(it) }.toTypedArray())
            intent.putExtra("subs.enable", arrayOf(Uri.parse(subs[0])))
        }
        if (!pkg.isNullOrEmpty()) intent.setPackage(pkg)
        return try {
            startActivity(if (pkg.isNullOrEmpty()) Intent.createChooser(intent, title) else intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    /** Installed apps that can play a video URL: list of [label, package]. */
    private fun videoPlayers(): List<List<String>> {
        val intent = videoIntent("http://127.0.0.1/video.mkv", "")
        @Suppress("DEPRECATION")
        val list = packageManager.queryIntentActivities(intent, 0)
        return list.map { listOf(it.loadLabel(packageManager).toString(), it.activityInfo.packageName) }
            .filter { it[1] != packageName }
            .distinctBy { it[1] }
            .sortedBy { it[0].lowercase() }
    }
}
