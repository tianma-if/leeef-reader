package dev.leeef.native_bridge

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.PixelCopy
import android.webkit.WebView
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import java.io.ByteArrayOutputStream

@InvokeArg
class CaptureWebviewRegionArgs {
    var x: Double = 0.0
    var y: Double = 0.0
    var width: Double = 0.0
    var height: Double = 0.0
}

/**
 * Window PixelCopy for the captured slide pipeline.
 *
 * Adapted from Readest's native-bridge (AGPL-3.0): JPEG, cap at 2x CSS
 * pixels, encode off the UI thread. PNG at 3x was ~1.5s on Xiaomi.
 */
@TauriPlugin
class NativeBridgePlugin(private val activity: Activity) : Plugin(activity) {
    private var webViewRef: WebView? = null

    override fun load(webView: WebView) {
        webViewRef = webView
        super.load(webView)
    }

    @Command
    fun capture_webview_region(invoke: Invoke) {
        val args = invoke.parseArgs(CaptureWebviewRegionArgs::class.java)
        val webView = webViewRef
        val window = activity.window
        if (webView == null || window == null) {
            invoke.reject("WebView not available")
            return
        }
        activity.runOnUiThread {
            val density = webView.resources.displayMetrics.density
            val location = IntArray(2)
            webView.getLocationInWindow(location)
            val left = location[0] + (args.x * density).toInt()
            val top = location[1] + (args.y * density).toInt()
            val width = (args.width * density).toInt()
            val height = (args.height * density).toInt()
            if (width <= 0 || height <= 0) {
                invoke.reject("Empty capture region")
                return@runOnUiThread
            }
            val captureScale = minOf(density, 2f)
            val destWidth = (args.width * captureScale).toInt().coerceAtLeast(1)
            val destHeight = (args.height * captureScale).toInt().coerceAtLeast(1)
            val bitmap = Bitmap.createBitmap(destWidth, destHeight, Bitmap.Config.ARGB_8888)
            try {
                PixelCopy.request(
                    window,
                    Rect(left, top, left + width, top + height),
                    bitmap,
                    { result ->
                        if (result == PixelCopy.SUCCESS) {
                            Thread {
                                val out = ByteArrayOutputStream()
                                bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
                                val data = Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
                                invoke.resolve(JSObject().put("data", data))
                            }.start()
                        } else {
                            invoke.reject("PixelCopy failed: $result")
                        }
                    },
                    Handler(Looper.getMainLooper()),
                )
            } catch (e: IllegalArgumentException) {
                invoke.reject("Capture region out of bounds: ${e.message}")
            }
        }
    }
}
