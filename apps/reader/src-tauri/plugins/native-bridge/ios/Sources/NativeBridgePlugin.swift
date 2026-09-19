import Tauri
import UIKit
import WebKit

class CaptureWebviewRegionArgs: Decodable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double
}

class NativeBridgePlugin: Plugin {
  @objc public func pick_books(_ invoke: Invoke) {
    invoke.resolve(["files": [] as [Any]])
  }
  /// WKWebView snapshot for the captured slide pipeline.
  /// Adapted from Readest (AGPL-3.0): cap at 2x CSS pixels, JPEG 0.9.
  @objc public func capture_webview_region(_ invoke: Invoke) {
    guard let args = try? invoke.parseArgs(CaptureWebviewRegionArgs.self) else {
      return invoke.reject("Failed to parse arguments")
    }
    DispatchQueue.main.async { [weak self] in
      guard let webView = self?.webView else {
        return invoke.reject("WebView not available")
      }
      let config = WKSnapshotConfiguration()
      config.rect = CGRect(x: args.x, y: args.y, width: args.width, height: args.height)
      let scale = webView.window?.screen.scale ?? UIScreen.main.scale
      if scale > 2 {
        config.snapshotWidth = NSNumber(value: args.width * 2.0 / scale)
      }
      webView.takeSnapshot(with: config) { image, error in
        guard let image = image else {
          return invoke.reject(error?.localizedDescription ?? "Snapshot failed")
        }
        DispatchQueue.global(qos: .userInteractive).async {
          guard let data = image.jpegData(compressionQuality: 0.9) else {
            return invoke.reject("JPEG encoding failed")
          }
          invoke.resolve(["data": data.base64EncodedString()])
        }
      }
    }
  }
}

@_cdecl("init_plugin_native_bridge")
func initPlugin() -> Plugin {
  return NativeBridgePlugin()
}
