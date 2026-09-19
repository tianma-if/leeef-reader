package dev.leeef.leeef_reader

import android.os.Bundle
import android.webkit.WebView
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

class MainActivity : TauriActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
  }

  override fun onWebViewCreate(webView: WebView) {
    ViewCompat.setOnApplyWindowInsetsListener(webView) { _, insets ->
      val bars = insets.getInsets(
        WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout(),
      )
      val density = webView.resources.displayMetrics.density
      pushSafeArea(webView, bars.top / density, bars.bottom / density)
      insets
    }
    ViewCompat.requestApplyInsets(webView)
  }

  private fun pushSafeArea(webView: WebView, top: Float, bottom: Float) {
    val js = """
      (function(){
        var r = document.documentElement;
        if (!r || !r.style) return;
        r.style.setProperty('--leeef-safe-top', '${top}px');
        r.style.setProperty('--leeef-safe-bottom', '${bottom}px');
      })();
    """.trimIndent()
    webView.evaluateJavascript(js, null)
    webView.postDelayed({ webView.evaluateJavascript(js, null) }, 200)
    webView.postDelayed({ webView.evaluateJavascript(js, null) }, 800)
  }
}
