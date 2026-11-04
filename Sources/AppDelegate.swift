import AppKit

/// A link waiting for the panel, with the app it was clicked in.
private struct Link {
    let url: URL
    let source: String?
    /// False for the "Try the picker" probe, which should not teach the model.
    var learn = true
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var queue: [Link] = []
    private var picker: PickerController?
    private var settings: SettingsWindowController?
    private var handledURL = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Opened from Spotlight or the Dock rather than by a link: show what it does.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !handledURL else { return }
            showSettings()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handledURL = true
        let source = Self.sender()
        queue.append(contentsOf: urls.filter { $0.scheme == "http" || $0.scheme == "https" }
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
            settings = SettingsWindowController { [weak self] in
                if let probe = URL(string: "https://example.com/what-this-looks-like") {
                    self?.queue.append(Link(url: probe, source: nil, learn: false))
                    self?.next()
                }
            }
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
            Launcher.open(url, in: rule.target)
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
