import Cocoa
import FlutterMacOS
import Sparkle

extension SUAppcast {
    func leeefDictionary() -> NSDictionary {
        ["items": items.map { $0.leeefDictionary() }]
    }
}

extension SUAppcastItem {
    func leeefDictionary() -> NSDictionary {
        [
            "versionString": versionString,
            "displayVersionString": displayVersionString,
            "fileURL": fileURL?.absoluteString ?? "",
            "contentLength": contentLength,
            "infoURL": infoURL?.absoluteString ?? "",
            "title": title ?? "",
            "dateString": dateString ?? "",
            "releaseNotesURL": releaseNotesURL?.absoluteString ?? "",
            "itemDescription": itemDescription ?? "",
            "itemDescriptionFormat": itemDescriptionFormat ?? "",
            "fullReleaseNotesURL": fullReleaseNotesURL ?? "",
            "minimumSystemVersion": minimumSystemVersion ?? "",
            "minimumOperatingSystemVersionIsOK": minimumOperatingSystemVersionIsOK,
            "maximumSystemVersion": maximumSystemVersion ?? "",
            "maximumOperatingSystemVersionIsOK": maximumOperatingSystemVersionIsOK,
            "channel": channel ?? "",
        ]
    }
}

final class AutoUpdater: NSObject, SPUUpdaterDelegate {
    private var userDriver: SPUStandardUserDriver?
    private var updater: SPUUpdater?
    private var feedURL: URL?
    private var immediateInstallHandler: (() -> Void)?
    var onEvent: ((String, NSDictionary) -> Void)?

    override init() {
        super.init()
        let hostBundle = Bundle.main
        userDriver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
        updater = SPUUpdater(
            hostBundle: hostBundle,
            applicationBundle: hostBundle,
            userDriver: userDriver!,
            delegate: self
        )
        updater?.clearFeedURLFromUserDefaults()
        try? updater?.start()
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        feedURL?.absoluteString
    }

    func setFeedURL(_ url: URL?) {
        feedURL = url
        try? updater?.start()
    }

    func checkForUpdates(inBackground: Bool) {
        if inBackground {
            updater?.checkForUpdatesInBackground()
        } else {
            updater?.checkForUpdates()
        }
    }

    func setScheduledCheckInterval(_ interval: Int) {
        updater?.updateCheckInterval = TimeInterval(interval)
    }

    func installDownloadedUpdate() -> Bool {
        guard let handler = immediateInstallHandler else { return false }
        immediateInstallHandler = nil
        DispatchQueue.main.async(execute: handler)
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        emit("error", ["error": error.localizedDescription])
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        emit("checking-for-update", ["appcast": appcast.leeefDictionary()])
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        emit("update-available", ["appcastItem": item.leeefDictionary()])
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        emit("update-not-available", ["error": error.localizedDescription])
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        self.immediateInstallHandler = immediateInstallHandler
        let data: NSDictionary = ["appcastItem": item.leeefDictionary()]
        emit("before-quit-for-update", data)
        // auto_updater already maps this event, while the second event moves
        // Leeef's UI to the ready state only after Sparkle exposes its safe
        // immediate-install handoff.
        emit("update-downloaded", data)
        return true
    }

    private func emit(_ eventName: String, _ data: NSDictionary) {
        onEvent?(eventName, data)
    }
}
