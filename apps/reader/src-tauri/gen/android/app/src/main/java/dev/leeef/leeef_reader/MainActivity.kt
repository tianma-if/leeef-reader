package dev.leeef.leeef_reader

import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewTreeObserver
import android.webkit.JavascriptInterface
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import java.util.Locale

class MainActivity : TauriActivity() {
  @Volatile private var safeTopCss = 0f
  @Volatile private var safeBottomCss = 0f
  @Volatile private var keyboardBottomCss = 0f
  private var insetWebView: WebView? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
  }

  override fun onResume() {
    super.onResume()
    insetWebView?.let { refreshSafeArea(it, forcePush = true) }
  }

  override fun onWindowFocusChanged(hasFocus: Boolean) {
    super.onWindowFocusChanged(hasFocus)
    if (hasFocus) insetWebView?.let { refreshSafeArea(it, forcePush = true) }
  }

  override fun onWebViewCreate(webView: WebView) {
    insetWebView = webView
    webView.addJavascriptInterface(SafeAreaBridge(this), "LeeefSafeArea")
    installDocumentStart(webView)
    // targetSdk 36 draws edge-to-edge. Insets dispatched to the WebView are
    // already consumed (bottom 0) while DecorView still paints the navigation
    // bar over the page. Read the window insets, and do not forward them into
    // WebView.onApplyWindowInsets: html already pads with --leeef-safe-*, and
    // a non-zero env(safe-area-inset-*) would pad the reader chrome again.
    ViewCompat.setOnApplyWindowInsetsListener(webView) { _, insets ->
      refreshSafeArea(webView, insets)
      webView.post { refreshSafeArea(webView, insets, forcePush = true) }
      insets
    }
    ViewCompat.requestApplyInsets(webView)
    // Posted before the WebView is attached, so both run from the attach queue:
    // the immediate pass wraps Tauri's client after setWebViewClient, and the
    // delayed pass runs again in case that client was installed later.
    webView.post {
      installPageHook(webView)
      webView.post { watchUntilMeasured(webView) }
    }
    webView.postDelayed({ installPageHook(webView) }, 50)
  }

  internal fun safeAreaTop(): String = cssPx(safeTopCss)

  internal fun safeAreaBottom(): String = cssPx(safeBottomCss)

  internal fun safeAreaKeyboard(): String = cssPx(keyboardBottomCss)

  private fun installDocumentStart(webView: WebView) {
    if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) return
    WebViewCompat.addDocumentStartJavaScript(
      webView,
      """
      (function(){
        try {
          var api = window.LeeefSafeArea;
          var root = document.documentElement;
          if (!api || !root || !root.style) return;
          root.style.setProperty('--leeef-safe-top', api.top());
          root.style.setProperty('--leeef-safe-bottom', api.bottom());
          root.style.setProperty('--leeef-keyboard-bottom', api.keyboard());
        } catch (e) {}
      })();
      """.trimIndent(),
      setOf("*"),
    )
  }

  private fun installPageHook(webView: WebView) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val inner = webView.webViewClient
    if (inner is SafeAreaWebViewClient) return
    webView.webViewClient = SafeAreaWebViewClient(inner) {
      refreshSafeArea(it, forcePush = true)
    }
  }

  private fun watchUntilMeasured(webView: WebView) {
    val listener = object : ViewTreeObserver.OnGlobalLayoutListener {
      var ticks = 0
      override fun onGlobalLayout() {
        refreshSafeArea(webView, forcePush = true)
        ticks += 1
        val measured = safeBottomCss > 0f || safeTopCss > 0f
        if ((measured && ticks >= 2) || ticks >= 8) {
          val observer = webView.viewTreeObserver
          if (observer.isAlive) observer.removeOnGlobalLayoutListener(this)
        }
      }
    }
    webView.viewTreeObserver.addOnGlobalLayoutListener(listener)
  }

  private fun refreshSafeArea(
    webView: WebView,
    dispatched: WindowInsetsCompat? = null,
    forcePush: Boolean = false,
  ) {
    val next = measureSafeArea(webView, dispatched)
    val changed = next != null && (
      next.top != safeTopCss || next.bottom != safeBottomCss || next.keyboard != keyboardBottomCss
    )
    if (next != null) {
      safeTopCss = next.top
      safeBottomCss = next.bottom
      keyboardBottomCss = next.keyboard
    }
    if (forcePush || changed) pushSafeArea(webView)
  }

  private fun measureSafeArea(webView: WebView, dispatched: WindowInsetsCompat?): SafeArea? {
    val native = window.decorView.rootWindowInsets ?: webView.rootWindowInsets
    val root = native?.let { WindowInsetsCompat.toWindowInsetsCompat(it) }
    if (root == null && dispatched == null && edgeOverlapPx("navigationBarBackground", bottom = true) == 0) {
      return null
    }
    val types = WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
    val rootBars = root?.let { barsOf(it, types) }
    val dispatchedBars = dispatched?.let { barsOf(it, types) }
    val top = maxOf(
      rootBars?.top ?: 0,
      dispatchedBars?.top ?: 0,
      edgeOverlapPx("statusBarBackground", bottom = false),
    )
    val bottom = maxOf(
      rootBars?.bottom ?: 0,
      dispatchedBars?.bottom ?: 0,
      edgeOverlapPx("navigationBarBackground", bottom = true),
    )
    val ime = maxOf(
      root?.getInsets(WindowInsetsCompat.Type.ime())?.bottom ?: 0,
      dispatched?.getInsets(WindowInsetsCompat.Type.ime())?.bottom ?: 0,
    )
    val density = webView.resources.displayMetrics.density.coerceAtLeast(1f)
    val keyboard = if (ime > bottom) ime / density else 0f
    return SafeArea(top / density, bottom / density, keyboard)
  }

  private fun barsOf(insets: WindowInsetsCompat, types: Int): androidx.core.graphics.Insets {
    val visible = insets.getInsets(types)
    val ignored = try {
      insets.getInsetsIgnoringVisibility(types)
    } catch (_: IllegalArgumentException) {
      visible
    }
    return androidx.core.graphics.Insets.of(
      maxOf(visible.left, ignored.left),
      maxOf(visible.top, ignored.top),
      maxOf(visible.right, ignored.right),
      maxOf(visible.bottom, ignored.bottom),
    )
  }

  private fun edgeOverlapPx(viewName: String, bottom: Boolean): Int {
    val id = resources.getIdentifier(viewName, "id", "android")
    if (id == 0) return 0
    val bar = window.decorView.findViewById<View>(id) ?: return 0
    if (bar.visibility != View.VISIBLE || bar.height <= 0) return 0
    val decorHeight = window.decorView.height
    if (decorHeight <= 0) return 0
    val cap = (96f * resources.displayMetrics.density).toInt().coerceAtLeast(1)
    val thickness = bar.height.coerceAtMost(cap)
    return if (bottom) {
      if (bar.top >= decorHeight / 2) thickness else 0
    } else if (bar.top <= 0 && bar.bottom <= decorHeight / 2) {
      thickness
    } else {
      0
    }
  }

  private fun pushSafeArea(webView: WebView) {
    val top = cssPx(safeTopCss)
    val bottom = cssPx(safeBottomCss)
    val keyboard = cssPx(keyboardBottomCss)
    webView.evaluateJavascript(
      """
      (function(){
        var root = document.documentElement;
        if (!root || !root.style) return;
        root.style.setProperty('--leeef-safe-top', '$top');
        root.style.setProperty('--leeef-safe-bottom', '$bottom');
        root.style.setProperty('--leeef-keyboard-bottom', '$keyboard');
      })();
      """.trimIndent(),
      null,
    )
  }

  private fun cssPx(value: Float): String = String.format(Locale.US, "%.4fpx", value)

  private data class SafeArea(val top: Float, val bottom: Float, val keyboard: Float)
}

class SafeAreaBridge(private val host: MainActivity) {
  @JavascriptInterface fun top(): String = host.safeAreaTop()

  @JavascriptInterface fun bottom(): String = host.safeAreaBottom()

  @JavascriptInterface fun keyboard(): String = host.safeAreaKeyboard()
}

private class SafeAreaWebViewClient(
  private val inner: WebViewClient,
  private val onReady: (WebView) -> Unit,
) : WebViewClient() {
  override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest) =
    inner.shouldInterceptRequest(view, request)

  override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) =
    inner.shouldOverrideUrlLoading(view, request)

  override fun onPageStarted(view: WebView, url: String, favicon: android.graphics.Bitmap?) {
    inner.onPageStarted(view, url, favicon)
  }

  override fun onPageCommitVisible(view: WebView, url: String) {
    inner.onPageCommitVisible(view, url)
    onReady(view)
  }

  override fun onPageFinished(view: WebView, url: String) {
    inner.onPageFinished(view, url)
    onReady(view)
  }

  override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
    inner.onReceivedError(view, request, error)
  }
}
