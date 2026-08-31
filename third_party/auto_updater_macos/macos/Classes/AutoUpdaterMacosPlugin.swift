import Cocoa
import FlutterMacOS

public final class AutoUpdaterMacosPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var pendingEvents: [[String: Any]] = []
    private let autoUpdater = AutoUpdater()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "dev.leanflutter.plugins/auto_updater",
            binaryMessenger: registrar.messenger
        )
        let instance = AutoUpdaterMacosPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        let eventChannel = FlutterEventChannel(
            name: "dev.leanflutter.plugins/auto_updater_event",
            binaryMessenger: registrar.messenger
        )
        eventChannel.setStreamHandler(instance)
        instance.autoUpdater.onEvent = { [weak instance] eventName, eventData in
            instance?.sendOrQueueEvent(type: eventName, data: eventData)
        }
    }

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        for event in pendingEvents {
            events(event)
        }
        pendingEvents.removeAll()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    private func sendOrQueueEvent(type: String, data: NSDictionary) {
        let event: [String: Any] = ["type": type, "data": data]
        if let eventSink {
            eventSink(event)
        } else {
            pendingEvents.append(event)
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "setFeedURL":
            autoUpdater.setFeedURL(URL(string: arguments["feedURL"] as? String ?? ""))
            result(true)
        case "checkForUpdates":
            autoUpdater.checkForUpdates(
                inBackground: arguments["inBackground"] as? Bool ?? false
            )
            result(true)
        case "setScheduledCheckInterval":
            autoUpdater.setScheduledCheckInterval(arguments["interval"] as? Int ?? 86400)
            result(true)
        case "installDownloadedUpdate":
            result(autoUpdater.installDownloadedUpdate())
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
