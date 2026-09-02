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
    private var started = false
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
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        feedURL?.absoluteString
    }

    func setFeedURL(_ url: URL?) throws {
        guard let url else {
            throw NSError(
                domain: "dev.leeef.auto_updater",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The update feed URL is invalid."]
            )
        }
        guard let updater else {
            throw NSError(
                domain: "dev.leeef.auto_updater",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The Sparkle updater is unavailable."]
            )
        }

        feedURL = url
        if !started {
            try updater.start()
            started = true
        }
    }

    func checkForUpdates(inBackground: Bool) throws {
        guard started else {
            throw NSError(
                domain: "dev.leeef.auto_updater",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "The Sparkle updater has not started."]
            )
        }
        // Starting Sparkle may already have scheduled a check for this runloop.
        // Do not collide with that session when Flutter requests its launch check.
        if updater?.sessionInProgress == true {
            return
        }
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
        let sparkleError = error as NSError
        if sparkleError.domain == SUSparkleErrorDomain && sparkleError.code == 1001 {
            // Sparkle reports "already up to date" as SUNoUpdateError (1001)
            // after an automatic cycle. That is an idle result, not a failure.
            emit("update-not-available", ["error": sparkleError.localizedDescription])
        } else {
            emit("error", ["error": detailedDescription(for: sparkleError)])
        }
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        emit("checking-for-update", ["appcast": appcast.leeefDictionary()])
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        emit("update-available", ["appcastItem": item.leeefDictionary()])
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        // Download completion alone is not enough to offer an immediate
        // restart. Sparkle still has to verify and extract the archive before
        // it supplies the safe installation handler below.
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
        // Move Flutter to ready only after Sparkle exposes its verified,
        // extracted update through the immediate-install handoff.
        emit("update-downloaded", data)
        return true
    }

    private func emit(_ eventName: String, _ data: NSDictionary) {
        onEvent?(eventName, data)
    }

    private func detailedDescription(for error: NSError) -> String {
        var details = [error.localizedDescription]
        if let reason = error.localizedFailureReason, !details.contains(reason) {
            details.append(reason)
        }
        if let suggestion = error.localizedRecoverySuggestion,
           !details.contains(suggestion) {
            details.append(suggestion)
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            let description = detailedDescription(for: underlying)
            if !details.contains(description) {
                details.append(description)
            }
        }
        return details.joined(separator: " ")
    }
}
