import AppKit
import Sparkle

/// A link waiting for the panel, with the app it was clicked in.
private struct Link {
    let url: URL
    let source: String?
    /// False for the "Try the picker" probe, which should not teach the model.
    var learn = true
}

final class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    private var queue: [Link] = []
    private var picker: PickerController?
    private var settings: SettingsWindowController?
    private var handledURL = false
    /// Links handed to a browser whose `open` hasn't finished yet.
    private var opening = 0
    /// Sparkle's handler for a downloaded update that is waiting for the app to quit.
    private var pendingInstall: (() -> Void)?
    private var installingQuietly = false
    private static let reopenedAfterQuietUpdate = "ReopenedAfterQuietUpdate"
    // Sparkle asks on the second launch whether to check automatically; until then it only
    // checks when asked to from the settings window.
    private lazy var updater = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)

    // A scheduled update alert waits behind other windows instead of taking focus from
    // whatever the user is doing, and the picker panel floats above it.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = updater
        // Sparkle reopening it after an update nobody watched is not a reason to show a window.
        let reopened = UserDefaults.standard.bool(forKey: Self.reopenedAfterQuietUpdate)
        UserDefaults.standard.removeObject(forKey: Self.reopenedAfterQuietUpdate)
        // Opened from Spotlight or the Dock rather than by a link: show what it does.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !handledURL, !reopened else { return }
            showSettings()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handledURL = true
        let source = Self.sender()
        // The default browser also gets .html files, so a double-clicked page arrives here
        // as a file URL next to the web links.
        queue.append(contentsOf: urls.filter { $0.isFileURL || $0.scheme == "http" || $0.scheme == "https" }
            .map { Link(url: $0, source: source) })
        next()
    }

    /// The app the link was clicked in. Slack and Mail say a lot about which identity
    /// a link belongs to; nil when macOS does not pass a sender along.
    private static func sender() -> String? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value,
              pid > 0, pid != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings()
        return true
    }

    private func showSettings() {
        if settings == nil {
            settings = SettingsWindowController(onTry: { [weak self] in
                if let probe = URL(string: "https://example.com/what-this-looks-like") {
                    self?.queue.append(Link(url: probe, source: nil, learn: false))
                    self?.next()
                }
            }, onCheckForUpdates: { [weak self] in
                self?.updater.checkForUpdates(nil)
            })
        }
        settings?.present()
    }

    private func next() {
        guard picker == nil, !queue.isEmpty else { return }
        let link = queue.removeFirst()
        let url = link.url
        let choices = Store.choices()

        guard !choices.isEmpty else {
            showSettings()
            return
        }
        if let rule = Store.rule(for: url, in: choices) {
            launch(url, in: rule.target)
            finished()
            return
        }

        let guess = Store.guess(for: url, source: link.source, in: choices)
        let controller = PickerController(url: url, choices: choices, highlight: guess.index,
                                          countdown: Store.countdown) { [weak self] choice, via in
            if link.learn {
                Store.record(Pick(time: Date(), url: url.absoluteString, source: link.source,
                                  guess: choices[guess.index].target.id, confidence: guess.confidence,
                                  target: choice?.target.id, via: via))
            }
            if let choice { self?.launch(url, in: choice.target) }
            self?.picker = nil
            self?.finished()
        }
        picker = controller
        controller.show()
    }

    private func launch(_ url: URL, in target: Target) {
        opening += 1
        Launcher.open(url, in: target) { [weak self] in
            guard let self else { return }
            opening -= 1
            installIfQuiet()
        }
    }

    private func finished() {
        if !queue.isEmpty {
            next()
            return
        }
        // Nothing left to ask about: get out of the way unless the settings window is open.
        if settings?.window?.isVisible != true {
            NSApp.hide(nil)
        }
        installIfQuiet()
    }

    // MARK: Updates

    /// Marks update checks from the owner's own Macs (`defaults write com.spashii.browserpicker
    /// OwnerMac -bool YES`) with `self=1` on the appcast URL, so the counts on apps.idea2prod.in
    /// can leave them out. Everyone else's checks carry no parameters; system profiling stays off.
    func feedParameters(for updater: SPUUpdater, sendingSystemProfile: Bool) -> [[String: String]] {
        UserDefaults.standard.bool(forKey: "OwnerMac") ? [["key": "self", "value": "1"]] : []
    }

    /// With automatic updates on, Sparkle downloads an update and installs it when the app
    /// quits, but Browser Picker runs until logout, so an update could wait for days. It takes
    /// the install over and runs it once no picker is open and no link is on its way to a
    /// browser: Sparkle then quits, installs the update and opens the new version.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        pendingInstall = immediateInstallHandler
        installIfQuiet()
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        if installingQuietly {
            UserDefaults.standard.set(true, forKey: Self.reopenedAfterQuietUpdate)
        }
    }

    /// No picker open and no link being routed. Called after each step that can end the work
    /// on a link, so a waiting update installs at the first quiet moment. An open panel is
    /// never quiet, also while its countdown runs: the countdown is about to open a link, and
    /// `picker` stays set until the panel has closed and handed its link to `launch`.
    private func installIfQuiet() {
        guard let install = pendingInstall, picker == nil, queue.isEmpty, opening == 0 else { return }
        pendingInstall = nil
        installingQuietly = true
        install()
    }
}
