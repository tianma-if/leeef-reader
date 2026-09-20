package dev.leeef.native_bridge

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.util.Base64
import android.util.Log
import android.view.Gravity
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.ImageView
import android.widget.PopupWindow
import androidx.activity.result.ActivityResult
import app.tauri.annotation.ActivityCallback
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSArray
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import java.io.ByteArrayOutputStream

@InvokeArg
class CaptureWebviewRegionArgs {
    var x: Double = 0.0
    var y: Double = 0.0
    var width: Double = 0.0
    var height: Double = 0.0
    var cover: Boolean = false
}

@InvokeArg
class CoverProgressArgs {
    var progress: Double = 0.0
    var forward: Boolean = true
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
    private var coverPopup: PopupWindow? = null
    private var coverImage: ImageView? = null
    private var coverWidth = 0

    override fun load(webView: WebView) {
        webViewRef = webView
        super.load(webView)
    }

    @Command
    fun pick_books(invoke: Invoke) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        startActivityForResult(invoke, intent, "onPickBooks")
    }

    @ActivityCallback
    private fun onPickBooks(invoke: Invoke, result: ActivityResult) {
        val payload = JSObject()
        val files = JSArray()
        payload.put("files", files)
        if (result.resultCode != Activity.RESULT_OK) {
            invoke.resolve(payload)
            return
        }
        val data = result.data
        val uris = mutableListOf<Uri>()
        val clip = data?.clipData
        if (clip != null) {
            for (index in 0 until clip.itemCount) {
                val uri = clip.getItemAt(index)?.uri
                if (uri != null) uris.add(uri)
            }
        }
        val single = data?.data
        if (uris.isEmpty() && single != null) {
            uris.add(single)
        }
        for (uri in uris) {
            try {
                activity.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (_: SecurityException) {
                // Some providers only grant a one-shot read.
            }
            val name = queryDisplayName(uri)
            val stream = activity.contentResolver.openInputStream(uri) ?: continue
            val bytes = stream.use { input -> input.readBytes() }
            files.put(
                JSObject()
                    .put("name", name)
                    .put("data", Base64.encodeToString(bytes, Base64.NO_WRAP)),
            )
        }
        invoke.resolve(payload)
    }

    private fun queryDisplayName(uri: Uri): String {
        val cursor = activity.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )
        cursor?.use {
            if (it.moveToFirst()) {
                val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return it.getString(index)
            }
        }
        return uri.lastPathSegment ?: "book"
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
            val windowRect = Rect(left, top, left + width, top + height)
            copyPixels(webView, window, windowRect, destWidth, destHeight) { bitmap ->
                if (bitmap == null) {
                    invoke.reject("PixelCopy failed")
                    return@copyPixels
                }
                if (args.cover) {
                    showCover(bitmap, windowRect)
                }
                Thread {
                    val out = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
                    val data = Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
                    invoke.resolve(JSObject().put("data", data))
                }.start()
            }
        }
    }

    @Command
    fun set_cover_progress(invoke: Invoke) {
        val args = invoke.parseArgs(CoverProgressArgs::class.java)
        activity.runOnUiThread {
            val width = coverWidth.toFloat()
            val shift = if (args.forward) -args.progress.toFloat() * width else args.progress.toFloat() * width
            coverImage?.translationX = shift
            invoke.resolve()
        }
    }

    @Command
    fun uncover_webview(invoke: Invoke) {
        activity.runOnUiThread {
            removeCover()
            invoke.resolve()
        }
    }

    @Command
    fun probe_webview_ready(invoke: Invoke) {
        val webView = webViewRef
        val window = activity.window
        if (webView == null || window == null) {
            invoke.resolve(JSObject().put("ready", false))
            return
        }
        activity.runOnUiThread {
            val sample = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
            val handler = Handler(Looper.getMainLooper())
            val surfaceView = findSurfaceView(webView)
            if (surfaceView != null && surfaceView.holder.surface.isValid) {
                try {
                    PixelCopy.request(surfaceView, sample, { result ->
                        invoke.resolve(
                            JSObject().put("ready", result == PixelCopy.SUCCESS && !isMostlyFlat(sample)),
                        )
                    }, handler)
                    return@runOnUiThread
                } catch (_: IllegalArgumentException) {
                    // Fall through to a window copy.
                }
            }
            try {
                PixelCopy.request(window, sample, { result ->
                    invoke.resolve(
                        JSObject().put("ready", result == PixelCopy.SUCCESS && !isMostlyFlat(sample)),
                    )
                }, handler)
            } catch (_: IllegalArgumentException) {
                invoke.resolve(JSObject().put("ready", false))
            }
        }
    }

    private fun showCover(bitmap: Bitmap, windowRect: Rect) {
        removeCover()
        val image = ImageView(activity)
        image.setImageBitmap(bitmap)
        image.scaleType = ImageView.ScaleType.FIT_XY
        val popup = PopupWindow(image, windowRect.width(), windowRect.height(), false)
        popup.isClippingEnabled = false
        popup.elevation = 128f
        val anchor = webViewRef ?: activity.window.decorView
        popup.showAtLocation(anchor, Gravity.NO_GRAVITY, windowRect.left, windowRect.top)
        coverPopup = popup
        coverImage = image
        coverWidth = windowRect.width()
    }

    private fun removeCover() {
        try {
            coverPopup?.dismiss()
        } catch (_: Exception) {
        }
        coverPopup = null
        coverImage = null
        coverWidth = 0
    }

    private fun copyPixels(
        webView: WebView,
        window: android.view.Window,
        windowRect: Rect,
        destWidth: Int,
        destHeight: Int,
        done: (Bitmap?) -> Unit,
    ) {
        val handler = Handler(Looper.getMainLooper())
        val texture = findTextureView(webView)
        if (texture != null) {
            val full = texture.bitmap
            if (full != null) {
                val cropped = cropAndScale(full, texture, windowRect, destWidth, destHeight)
                if (cropped != null && !isMostlyFlat(cropped)) {
                    Log.i(CAPTURE_TAG, "texture-view ${cropped.width}x${cropped.height}")
                    done(cropped)
                    return
                }
            }
        }
        val surfaceView = findSurfaceView(webView)
        if (surfaceView != null && surfaceView.holder.surface.isValid) {
            val src = rectOnView(surfaceView, windowRect)
            val bitmap = Bitmap.createBitmap(destWidth, destHeight, Bitmap.Config.ARGB_8888)
            try {
                PixelCopy.request(surfaceView, src, bitmap, { result ->
                    if (result == PixelCopy.SUCCESS && !isMostlyFlat(bitmap)) {
                        Log.i(CAPTURE_TAG, "surface-view ${bitmap.width}x${bitmap.height}")
                        done(bitmap)
                    } else {
                        copyWindow(window, windowRect, destWidth, destHeight, handler, done)
                    }
                }, handler)
                return
            } catch (_: IllegalArgumentException) {
                // Fall through to the window copy.
            }
        }
        copyWindow(window, windowRect, destWidth, destHeight, handler, done)
    }

    private fun copyWindow(
        window: android.view.Window,
        windowRect: Rect,
        destWidth: Int,
        destHeight: Int,
        handler: Handler,
        done: (Bitmap?) -> Unit,
    ) {
        val decor = window.decorView
        val src = Rect(
            windowRect.left.coerceIn(0, (decor.width - 1).coerceAtLeast(0)),
            windowRect.top.coerceIn(0, (decor.height - 1).coerceAtLeast(0)),
            windowRect.right.coerceIn(1, decor.width.coerceAtLeast(1)),
            windowRect.bottom.coerceIn(1, decor.height.coerceAtLeast(1)),
        )
        if (src.width() <= 0 || src.height() <= 0) {
            done(null)
            return
        }
        val bitmap = Bitmap.createBitmap(destWidth, destHeight, Bitmap.Config.ARGB_8888)
        try {
            PixelCopy.request(window, src, bitmap, { result ->
                if (result == PixelCopy.SUCCESS && !isMostlyFlat(bitmap)) {
                    Log.i(CAPTURE_TAG, "window ${bitmap.width}x${bitmap.height}")
                    done(bitmap)
                    return@request
                }
                val drawn = drawWebView(webViewRef, windowRect, destWidth, destHeight)
                if (drawn != null && !isMostlyFlat(drawn)) {
                    Log.i(CAPTURE_TAG, "webview-draw ${drawn.width}x${drawn.height}")
                    done(drawn)
                } else {
                    Log.w(CAPTURE_TAG, "flat capture result=$result")
                    done(if (result == PixelCopy.SUCCESS) bitmap else drawn)
                }
            }, handler)
        } catch (e: IllegalArgumentException) {
            val drawn = drawWebView(webViewRef, windowRect, destWidth, destHeight)
            done(drawn)
        }
    }

    private fun drawWebView(
        webView: WebView?,
        windowRect: Rect,
        destWidth: Int,
        destHeight: Int,
    ): Bitmap? {
        if (webView == null || webView.width <= 0 || webView.height <= 0) return null
        val location = IntArray(2)
        webView.getLocationInWindow(location)
        val bitmap = Bitmap.createBitmap(destWidth, destHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val scaleX = destWidth.toFloat() / windowRect.width().coerceAtLeast(1)
        val scaleY = destHeight.toFloat() / windowRect.height().coerceAtLeast(1)
        canvas.scale(scaleX, scaleY)
        canvas.translate(
            (location[0] - windowRect.left).toFloat(),
            (location[1] - windowRect.top).toFloat(),
        )
        webView.draw(canvas)
        return bitmap
    }

    private fun cropAndScale(
        full: Bitmap,
        view: View,
        windowRect: Rect,
        destWidth: Int,
        destHeight: Int,
    ): Bitmap? {
        val location = IntArray(2)
        view.getLocationInWindow(location)
        val left = (windowRect.left - location[0]).coerceIn(0, (full.width - 1).coerceAtLeast(0))
        val top = (windowRect.top - location[1]).coerceIn(0, (full.height - 1).coerceAtLeast(0))
        val width = windowRect.width().coerceAtMost(full.width - left).coerceAtLeast(1)
        val height = windowRect.height().coerceAtMost(full.height - top).coerceAtLeast(1)
        if (left + width > full.width || top + height > full.height) return null
        val cropped = Bitmap.createBitmap(full, left, top, width, height)
        return Bitmap.createScaledBitmap(cropped, destWidth, destHeight, true)
    }

    private fun rectOnView(view: View, windowRect: Rect): Rect {
        val location = IntArray(2)
        view.getLocationInWindow(location)
        return Rect(
            (windowRect.left - location[0]).coerceAtLeast(0),
            (windowRect.top - location[1]).coerceAtLeast(0),
            (windowRect.right - location[0]).coerceAtMost(view.width),
            (windowRect.bottom - location[1]).coerceAtMost(view.height),
        )
    }

    private fun isMostlyFlat(bitmap: Bitmap): Boolean {
        val stepX = (bitmap.width / 8).coerceAtLeast(1)
        val stepY = (bitmap.height / 8).coerceAtLeast(1)
        var minL = 255
        var maxL = 0
        var y = 0
        while (y < bitmap.height) {
            var x = 0
            while (x < bitmap.width) {
                val color = bitmap.getPixel(x, y)
                val luma = (Color.red(color) * 3 + Color.green(color) * 6 + Color.blue(color)) / 10
                if (luma < minL) minL = luma
                if (luma > maxL) maxL = luma
                x += stepX
            }
            y += stepY
        }
        return maxL - minL < 18
    }

    private fun findSurfaceView(view: View): SurfaceView? {
        if (view is SurfaceView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findSurfaceView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }

    private fun findTextureView(view: View): TextureView? {
        if (view is TextureView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findTextureView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }

    companion object {
        private const val CAPTURE_TAG = "LeeefCapture"
    }
}
