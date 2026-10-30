package com.homestream.home_stream

import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.plugin.common.MethodChannel

/**
 * Android TV video layer: a SurfaceView under the (transparent) Flutter
 * surface. mpv's MediaCodec decoder renders the video straight into it
 * (vo=mediacodec_embed), so the TV box puts it on its own video plane like
 * its built-in player does for USB files: full 4K, HDR, the box's picture
 * processing and no per-frame copies. The Flutter player controls are drawn
 * on top, and the player screen leaves the video area transparent.
 */
class VideoLayer(private val activity: Activity, private val channel: MethodChannel) {
    private val handler = Handler(Looper.getMainLooper())
    private var container: FrameLayout? = null
    private var view: SurfaceView? = null

    /** JNI global reference of the surface, which mpv takes as `wid`. */
    private var wid = 0L
    private var videoW = 0
    private var videoH = 0

    fun show() {
        if (container != null) {
            // a new player took over: tell it about the existing surface
            channel.invokeMethod("surface", mapOf("wid" to wid))
            return
        }
        val root = activity.findViewById<ViewGroup>(android.R.id.content) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Android outlines the focused view (the Flutter view) once a
            // remote key is pressed; drawn under the transparent Flutter
            // surface it would frame the video
            for (i in 0 until root.childCount) root.getChildAt(i).defaultFocusHighlightEnabled = false
        }
        val box = FrameLayout(activity).apply {
            // letterbox bars
            setBackgroundColor(Color.BLACK)
            isFocusable = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
        val sv = SurfaceView(activity).apply { isFocusable = false }
        sv.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                if (wid != 0L) release()
                wid = newGlobalRef(holder.surface)
                channel.invokeMethod("surface", mapOf("wid" to wid))
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

            override fun surfaceDestroyed(holder: SurfaceHolder) = release()
        })
        val match = ViewGroup.LayoutParams.MATCH_PARENT
        box.addView(sv, FrameLayout.LayoutParams(match, match, Gravity.CENTER))
        box.addOnLayoutChangeListener { _, l, t, r, b, ol, ot, or, ob ->
            if (r - l != or - ol || b - t != ob - ot) box.post { fit() }
        }
        // below the Flutter view
        root.addView(box, 0, ViewGroup.LayoutParams(match, match))
        container = box
        view = sv
    }

    fun hide() {
        val box = container ?: return
        container = null
        view = null
        videoW = 0
        videoH = 0
        // removing the view destroys the surface (-> release)
        (box.parent as? ViewGroup)?.removeView(box)
        if (wid != 0L) release()
    }

    /** The video's display size: the surface keeps its aspect ratio. */
    fun setVideoSize(w: Int, h: Int) {
        videoW = w
        videoH = h
        fit()
    }

    private fun fit() {
        val box = container ?: return
        val sv = view ?: return
        val bw = box.width
        val bh = box.height
        if (bw <= 0 || bh <= 0) return
        var w = bw
        var h = bh
        if (videoW > 0 && videoH > 0) {
            if (bw.toLong() * videoH > bh.toLong() * videoW) {
                w = (bh.toLong() * videoW / videoH).toInt()
            } else {
                h = (bw.toLong() * videoH / videoW).toInt()
            }
        }
        val lp = sv.layoutParams as FrameLayout.LayoutParams
        if (lp.width != w || lp.height != h) {
            lp.width = w
            lp.height = h
            lp.gravity = Gravity.CENTER
            sv.layoutParams = lp
        }
    }

    private fun release() {
        val old = wid
        wid = 0L
        channel.invokeMethod("surface", mapOf("wid" to 0L))
        // mpv lets go of the surface asynchronously: free the reference later
        if (old != 0L) handler.postDelayed({ deleteGlobalRef(old) }, 5000)
    }

    // The JNI helper ships with media_kit's Android libraries; reflection
    // keeps this file independent of the plugin's compile classpath.
    private val helper: Class<*>? by lazy {
        try {
            Class.forName("com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper")
        } catch (e: Throwable) {
            Log.e(TAG, "media_kit helper missing", e)
            null
        }
    }

    private fun newGlobalRef(o: Any): Long = try {
        helper?.getDeclaredMethod("newGlobalObjectRef", Any::class.java)
            ?.invoke(null, o) as? Long ?: 0L
    } catch (e: Throwable) {
        Log.e(TAG, "newGlobalObjectRef", e)
        0L
    }

    private fun deleteGlobalRef(ref: Long) {
        try {
            helper?.getDeclaredMethod("deleteGlobalObjectRef", Long::class.javaPrimitiveType)
                ?.invoke(null, ref)
        } catch (e: Throwable) {
            Log.e(TAG, "deleteGlobalObjectRef", e)
        }
    }

    companion object {
        private const val TAG = "VideoLayer"
    }
}
