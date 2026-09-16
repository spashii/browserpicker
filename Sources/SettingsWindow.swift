import AppKit

final class SettingsWindowController: NSWindowController {
    private let statusField = NSTextField(labelWithString: "")
    private let defaultButton = NSButton(title: "Make Browser Picker the default", target: nil, action: nil)
    private var onTry: (() -> Void)?

    convenience init(onTry: @escaping () -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Browser Picker"
        window.center()
        self.init(window: window)
        self.onTry = onTry
        window.contentView = buildContent()
        refresh()
    }

    private func buildContent() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "Links open here, and you pick where they go.")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(heading)

        statusField.font = .systemFont(ofSize: 12)
        statusField.textColor = .secondaryLabelColor
        stack.addArrangedSubview(statusField)

        defaultButton.target = self
        defaultButton.action = #selector(makeDefault)
        stack.addArrangedSubview(defaultButton)

        stack.addArrangedSubview(separator())

        let listTitle = NSTextField(labelWithString: "Destinations")
        listTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        stack.addArrangedSubview(listTitle)

        let list = NSTextField(wrappingLabelWithString: destinations())
        list.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        list.textColor = .secondaryLabelColor
        stack.addArrangedSubview(list)

        stack.addArrangedSubview(separator())

        let path = NSTextField(wrappingLabelWithString: "Rename, reorder, hide or set host rules in\n\(Store.configURL.path)")
        path.font = .systemFont(ofSize: 11)
        path.textColor = .secondaryLabelColor
        stack.addArrangedSubview(path)

        let buttons = NSStackView(views: [
            button("Edit config", #selector(editConfig)),
            button("Try the picker", #selector(tryPicker)),
            button("Quit", #selector(quit)),
        ])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        stack.addArrangedSubview(buttons)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 380))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
        ])
        return container
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 420).isActive = true
        return line
    }

    private func destinations() -> String {
        Store.choices().map { "\($0.key.uppercased())   \($0.name)" }.joined(separator: "\n")
    }

    private func refresh() {
        let isDefault = Store.isDefaultBrowser
        statusField.stringValue = isDefault
            ? "Browser Picker is your default browser."
            : "Not the default browser yet, so links still go straight to another app."
        defaultButton.isHidden = isDefault
    }

    @objc private func makeDefault() {
        guard let bundle = Bundle.main.bundleURL as URL? else { return }
        if #available(macOS 14.0, *) {
            NSWorkspace.shared.setDefaultApplication(at: bundle, toOpenURLsWithScheme: "http") { [weak self] _ in
                NSWorkspace.shared.setDefaultApplication(at: bundle, toOpenURLsWithScheme: "https") { _ in
                    DispatchQueue.main.async { self?.refresh() }
                }
            }
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
        }
    }

    @objc private func editConfig() {
        if !FileManager.default.fileExists(atPath: Store.configURL.path) { _ = Store.choices() }
        NSWorkspace.shared.selectFile(Store.configURL.path, inFileViewerRootedAtPath: Store.directory.path)
    }

    @objc private func tryPicker() { onTry?() }

    @objc private func quit() { NSApp.terminate(nil) }

    func present() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

extension Store {
    static var isDefaultBrowser: Bool {
        guard let probe = URL(string: "https://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: probe)
        else { return false }
        return handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }
}
