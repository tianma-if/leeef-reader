import AVFoundation
import Network
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
  private var appStoreURL = URL(string: "https://apps.apple.com/app/id6805425493")!

  @objc public override func load(webview: WKWebView) {
    self.webView = webview
  }

  @objc public func browse_pairing_devices(_ invoke: Invoke) {
    DispatchQueue.main.async {
      let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_leeef-pair._tcp", domain: "local."), using: .tcp)
      var devices: [[String: Any]] = []
      var denied = false
      browser.stateUpdateHandler = { state in
        if case .waiting(.dns(let code)) = state, code == -65570 {
          denied = true
        } else if case .ready = state {
          denied = false
        }
      }
      browser.browseResultsChangedHandler = { results, _ in
        devices = results.compactMap { result in
          guard case .bonjour(let txt) = result.metadata,
            let name = txt["name"], let id = txt["id"], let key = txt["key"],
            let expiry = txt["expires"].flatMap(UInt64.init),
            let port = txt["port"].flatMap(UInt16.init),
            let addresses = txt["addresses"]
          else { return nil }
          return [
            "name": name, "sessionId": id, "hostPublicKey": key,
            "expiresAt": expiry, "port": port,
            "addresses": addresses.split(separator: ",").map(String.init),
          ]
        }
      }
      browser.start(queue: .main)
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
        browser.cancel()
        if denied && devices.isEmpty {
          invoke.reject("请在 iPhone 设置中允许 Leeef 访问局域网，或导入配置文件。")
        } else {
          invoke.resolve(["devices": devices])
        }
      }
    }
  }

  @objc public func scan_pairing_qr(_ invoke: Invoke) {
    let openScanner = { [weak self] (allowed: Bool) in
      DispatchQueue.main.async {
        guard allowed else {
          return invoke.reject("请在系统设置中允许 Leeef 使用相机，或选择导入配置文件。")
        }
        guard var presenter = self?.webView?.window?.rootViewController else {
          return invoke.reject("无法打开相机。")
        }
        while let presented = presenter.presentedViewController { presenter = presented }
        let scanner = PairingQrScanner { text, error in
          if let error { invoke.reject(error) }
          else { invoke.resolve(["text": text as Any? ?? NSNull()]) }
        }
        scanner.modalPresentationStyle = .fullScreen
        presenter.present(scanner, animated: true)
      }
    }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: openScanner(true)
    case .notDetermined: AVCaptureDevice.requestAccess(for: .video, completionHandler: openScanner)
    default: openScanner(false)
    }
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

  @objc public func check_mobile_update(_ invoke: Invoke) {
    guard let lookupURL = URL(string: "https://itunes.apple.com/lookup?id=6805425493") else {
      return invoke.resolve(updatePayload(state: "unavailable"))
    }
    let request = URLRequest(
      url: lookupURL,
      cachePolicy: .reloadRevalidatingCacheData,
      timeoutInterval: 15
    )
    URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
      guard
        error == nil,
        let data,
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let results = object["results"] as? [[String: Any]],
        let result = results.first,
        let storeVersion = result["version"] as? String
      else {
        return invoke.resolve(self?.updatePayload(state: "unavailable") ?? [
          "platform": "ios",
          "state": "unavailable",
        ])
      }
      if let storeURL = result["trackViewUrl"] as? String, let url = URL(string: storeURL) {
        self?.appStoreURL = url
      }
      let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
      let available = storeVersion.compare(currentVersion, options: .numeric) == .orderedDescending
      invoke.resolve(
        self?.updatePayload(
          state: available ? "available" : "idle",
          availableVersion: available ? storeVersion : nil
        ) ?? ["platform": "ios", "state": "unavailable"]
      )
    }.resume()
  }

  @objc public func start_mobile_update(_ invoke: Invoke) {
    openAppStore(invoke)
  }

  @objc public func complete_mobile_update(_ invoke: Invoke) {
    openAppStore(invoke)
  }

  @objc public func open_mobile_store(_ invoke: Invoke) {
    openAppStore(invoke)
  }

  private func openAppStore(_ invoke: Invoke) {
    DispatchQueue.main.async { [weak self] in
      guard let url = self?.appStoreURL else {
        return invoke.reject("App Store URL unavailable")
      }
      UIApplication.shared.open(url, options: [:]) { opened in
        if opened {
          invoke.resolve()
        } else {
          invoke.reject("无法打开 App Store")
        }
      }
    }
  }

  private func updatePayload(
    state: String,
    availableVersion: String? = nil
  ) -> [String: Any] {
    var payload: [String: Any] = [
      "platform": "ios",
      "state": state,
      "currentVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
    ]
    if let availableVersion {
      payload["availableVersion"] = availableVersion
    }
    return payload
  }
}

@_cdecl("init_plugin_native_bridge")
func initPlugin() -> Plugin {
  return NativeBridgePlugin()
}
