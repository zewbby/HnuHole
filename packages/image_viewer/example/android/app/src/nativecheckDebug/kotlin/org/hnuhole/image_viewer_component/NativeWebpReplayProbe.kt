package org.hnuhole.image_viewer_component

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Rect
import android.graphics.drawable.Animatable2
import android.graphics.drawable.AnimatedImageDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.PixelCopy
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONObject
import java.security.MessageDigest

/** Stock Android decoder control. No media access, export, or Flutter bridge. */
class NativeWebpReplayProbe : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private var animation: AnimatedImageDrawable? = null
    private var sample: Bitmap? = null
    private var active = false
    private var foreground = false
    private var startedAt = 0L
    private var lastColor = ""
    private var fixture = ""

    private fun event(stage: String, vararg values: Pair<String, Any>) {
        val payload = JSONObject().put("stage", stage).put("fixture", fixture)
        for ((key, value) in values) payload.put(key, value)
        if (startedAt != 0L) payload.put("elapsedMs", SystemClock.uptimeMillis() - startedAt)
        Log.i("VIEWER_NATIVE_REPLAY", payload.toString())
    }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        fixture = when (intent.getStringExtra("fixture")) {
            "slow" -> "animation_replay_slow.webp"
            "infinite" -> "animation_infinite.webp"
            "short" -> "animation.webp"
            "slowIdentity" -> "replay_identity_slow.webp"
            "fastIdentity" -> "replay_identity_fast.webp"
            else -> { finish(); return }
        }
        val title = TextView(this).apply {
            text = "Android 系统解码对照（仅合成测试）\n$fixture"
            textSize = 18f
        }
        val image = ImageView(this).apply { scaleType = ImageView.ScaleType.FIT_CENTER }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.WHITE)
            addView(title)
            addView(image, LinearLayout.LayoutParams(-1, 0, 1f))
            addView(Button(this@NativeWebpReplayProbe).apply {
                text = "关闭对照"
                setOnClickListener { finish() }
            })
        }
        setContentView(content)
        if (Build.VERSION.SDK_INT < 28) {
            title.append("\n需要 API28+；本对照未运行")
            event("unsupportedApi", "api" to Build.VERSION.SDK_INT)
            return
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val asset = "flutter_assets/assets/fixtures/$fixture"
        try {
            val bytes = assets.open(asset).use { it.readBytes() }
            val sha = MessageDigest.getInstance("SHA-256").digest(bytes)
                .joinToString("") { "%02x".format(it.toInt() and 255) }
            val drawable = ImageDecoder.decodeDrawable(ImageDecoder.createSource(assets, asset))
            if (drawable !is AnimatedImageDrawable) {
                event("notAnimated", "bytes" to bytes.size, "sha256" to sha)
                return
            }
            animation = drawable
            image.setImageDrawable(drawable)
            event("decoded", "bytes" to bytes.size, "sha256" to sha,
                "repeatCount" to drawable.repeatCount, "runningBeforeStart" to drawable.isRunning)
            drawable.registerAnimationCallback(object : Animatable2.AnimationCallback() {
                override fun onAnimationStart(drawable: Drawable) { event("started") }
                override fun onAnimationEnd(drawable: Drawable) { event("ended") }
            })
            image.postDelayed({
                if (!foreground || isFinishing || isDestroyed) return@postDelayed
                active = true
                startedAt = SystemClock.uptimeMillis()
                drawable.start() // Keep the file's repeat count; never override it.
                sample = Bitmap.createBitmap(8, 8, Bitmap.Config.ARGB_8888)
                sampleFrame(image)
                handler.postDelayed({
                    if (active) {
                        event("observationEnded", "running" to drawable.isRunning)
                        active = false
                        drawable.stop()
                    }
                }, 14000)
            }, 400)
        } catch (failure: Exception) {
            event("decodeFailed", "type" to failure.javaClass.simpleName)
            title.append("\n解码失败；见本任务诊断日志")
        }
    }

    private fun sampleFrame(image: ImageView) {
        if (!active || Build.VERSION.SDK_INT < 28) return
        val bitmap = sample ?: return
        val location = IntArray(2)
        image.getLocationInWindow(location)
        val position = if (fixture.startsWith("replay_identity_")) {
            // The identity label occupies the upper half; observe the colored
            // lower band using the actual FIT_CENTER image matrix.
            floatArrayOf(96f, 122f).also { image.imageMatrix.mapPoints(it) }
        } else {
            floatArrayOf(image.width / 2f, image.height / 2f)
        }
        val x = location[0] + position[0].toInt()
        val y = location[1] + position[1].toInt()
        // Observe only an 8x8 center of this synthetic image. No screenshot files.
        PixelCopy.request(window, Rect(x - 4, y - 4, x + 4, y + 4), bitmap, { result ->
            if (!active) return@request
            if (result == PixelCopy.SUCCESS) {
                val pixel = bitmap.getPixel(4, 4)
                val color = when {
                    Color.red(pixel) > 160 && Color.green(pixel) < 90 && Color.blue(pixel) < 90 -> "red"
                    Color.green(pixel) > 90 && Color.red(pixel) < 90 && Color.blue(pixel) < 90 -> "green"
                    Color.blue(pixel) > 160 && Color.red(pixel) < 90 && Color.green(pixel) < 90 -> "blue"
                    else -> "other"
                }
                if (color != lastColor) {
                    lastColor = color
                    event("visibleColor", "color" to color)
                }
            } else {
                event("sampleFailed", "result" to result)
            }
            handler.postDelayed({ sampleFrame(image) }, 100)
        }, handler)
    }

    override fun onStart() {
        super.onStart()
        foreground = true
    }

    override fun onStop() {
        foreground = false
        active = false
        handler.removeCallbacksAndMessages(null)
        animation?.stop()
        animation?.clearAnimationCallbacks()
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onStop()
    }

    override fun onDestroy() {
        // An in-flight PixelCopy may still own the tiny bitmap; release by GC.
        sample = null
        animation = null
        super.onDestroy()
    }
}
