import Tauri
import UIKit
import WebKit

class CaptureWebviewRegionArgs: Decodable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double
}

class SaveTextFileArgs: Decodable {
  let filename: String
  let content: String
}

class NativeBridgePlugin: Plugin {
  private weak var webView: WKWebView?

  @objc public override func load(webview: WKWebView) {
    self.webView = webview
  }

  @objc public func pick_books(_ invoke: Invoke) {
    invoke.resolve(["files": [] as [Any]])
  }

  @objc public func save_text_file(_ invoke: Invoke) {
    guard let args = try? invoke.parseArgs(SaveTextFileArgs.self) else {
      return invoke.reject("Failed to parse arguments")
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(args.filename)
    do {
      try args.content.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      return invoke.reject("无法准备导出文件：\(error.localizedDescription)")
    }
    DispatchQueue.main.async { [weak self] in
      guard let controller = self?.webView?.window?.rootViewController else {
        return invoke.reject("View controller not available")
      }
      let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      if let popover = activity.popoverPresentationController {
        popover.sourceView = self?.webView
        popover.sourceRect = self?.webView?.bounds ?? .zero
      }
      activity.completionWithItemsHandler = { _, completed, _, _ in
        try? FileManager.default.removeItem(at: url)
        invoke.resolve(["saved": completed])
      }
      controller.present(activity, animated: true)
    }
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

  @objc public func set_cover_progress(_ invoke: Invoke) {
    invoke.resolve()
  }

  @objc public func uncover_webview(_ invoke: Invoke) {
    invoke.resolve()
  }

  @objc public func probe_webview_ready(_ invoke: Invoke) {
    invoke.resolve(["ready": true])
  }
}

@_cdecl("init_plugin_native_bridge")
func initPlugin() -> Plugin {
  return NativeBridgePlugin()
}
