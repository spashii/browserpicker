import AppKit
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    private var queue: [URL] = []
    private var picker: PickerController?
    private var settings: SettingsWindowController?
    private var handledURL = false
    // Sparkle asks on the second launch whether to check automatically; until then it only
    // checks when asked to from the settings window.
    private lazy var updater = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)

    // A scheduled update alert waits behind other windows instead of taking focus from
    // whatever the user is doing, and the picker panel floats above it.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = updater
        // Opened from Spotlight or the Dock rather than by a link: show what it does.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !handledURL else { return }
            showSettings()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handledURL = true
        queue.append(contentsOf: urls.filter { $0.scheme == "http" || $0.scheme == "https" })
        next()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings()
        return true
    }

    private func showSettings() {
        if settings == nil {
            settings = SettingsWindowController(onTry: { [weak self] in
                if let probe = URL(string: "https://example.com/what-this-looks-like") {
                    self?.queue.append(probe)
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
        let url = queue.removeFirst()
        let choices = Store.choices()

        guard !choices.isEmpty else {
            showSettings()
            return
        }
        if let rule = Store.rule(for: url, in: choices) {
            Launcher.open(url, in: rule.target)
            finished()
            return
        }

        let controller = PickerController(url: url, choices: choices) { [weak self] choice in
            if let choice { Launcher.open(url, in: choice.target) }
            self?.picker = nil
            self?.finished()
        }
        picker = controller
        controller.show()
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
    }
}
