import AppKit

private enum Metric {
    static let width: CGFloat = 400
    static let row: CGFloat = 44
    static let header: CGFloat = 54
    static let pad: CGFloat = 8
    static let corner: CGFloat = 14
}

final class RowView: NSView {
    let choice: Choice
    var onActivate: (() -> Void)?
    var onHover: (() -> Void)?

    var isSelected = false {
        didSet {
            nameField.textColor = isSelected ? .white : .labelColor
            keyField.textColor = isSelected ? .white : .secondaryLabelColor
            keyField.layer?.backgroundColor = (isSelected ? NSColor.white.withAlphaComponent(0.22)
                                                          : NSColor.labelColor.withAlphaComponent(0.08)).cgColor
            needsDisplay = true
        }
    }

    /// What is left of the countdown, 1 to 0, on the row it will open. Nil when not counting.
    var progress: CGFloat? {
        didSet { needsDisplay = true }
    }

    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let keyField = NSTextField(labelWithString: "")

    init(choice: Choice) {
        self.choice = choice
        super.init(frame: NSRect(x: 0, y: 0, width: Metric.width, height: Metric.row))
        wantsLayer = true

        iconView.image = choice.target.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.frame = NSRect(x: 16, y: (Metric.row - 26) / 2, width: 26, height: 26)
        addSubview(iconView)

        nameField.stringValue = choice.name
        nameField.font = .systemFont(ofSize: 13.5, weight: .medium)
        nameField.lineBreakMode = .byTruncatingTail
        nameField.frame = NSRect(x: 52, y: (Metric.row - 18) / 2, width: Metric.width - 52 - 52, height: 18)
        addSubview(nameField)

        keyField.stringValue = choice.key.uppercased()
        keyField.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        keyField.alignment = .center
        keyField.wantsLayer = true
        keyField.layer?.cornerRadius = 5
        keyField.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        keyField.frame = NSRect(x: Metric.width - 16 - 22, y: (Metric.row - 18) / 2, width: 22, height: 18)
        keyField.isHidden = choice.key.isEmpty
        addSubview(keyField)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        let box = NSRect(x: Metric.pad, y: 1, width: bounds.width - Metric.pad * 2, height: bounds.height - 2)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()

        // The countdown drains under the name, inside the row that will open.
        guard let progress else { return }
        let track = NSRect(x: 52, y: 5, width: bounds.width - 52 - 16, height: 3)
        NSColor.white.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
        var bar = track
        bar.size.width *= max(0, min(1, progress))
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseUp(with event: NSEvent) { onActivate?() }
}

final class PickerContentView: NSVisualEffectView {
    var onKey: ((NSEvent) -> Bool)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
}

final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PickerController: NSObject {
    private let url: URL
    private let choices: [Choice]
    private let highlight: Int
    private let countdown: TimeInterval
    /// The choice, or nil, and how it was made: key, click, return, timer, escape, copy, away.
    private let finish: (Choice?, String) -> Void
    private var panel: PickerPanel!
    private var rows: [RowView] = []
    private var selected = 0
    private var observer: Any?
    private var timer: Timer?
    /// The panel opens under the pointer, so a row can land under it without a move.
    /// Only a pointer that has moved since counts as choosing.
    private let pointer = NSEvent.mouseLocation

    init(url: URL, choices: [Choice], highlight: Int, countdown: TimeInterval,
         finish: @escaping (Choice?, String) -> Void) {
        self.url = url
        self.choices = choices
        self.highlight = highlight
        self.countdown = countdown
        self.finish = finish
        super.init()
        build()
    }

    private func build() {
        let height = Metric.header + CGFloat(choices.count) * Metric.row + Metric.pad
        panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: Metric.width, height: height),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false

        let content = PickerContentView(frame: NSRect(x: 0, y: 0, width: Metric.width, height: height))
        content.material = .popover
        content.blendingMode = .behindWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = Metric.corner
        content.layer?.masksToBounds = true
        content.onKey = { [weak self] event in self?.handle(event) ?? false }
        panel.contentView = content

        // A file has no host: show its name, and the folder it sits in below.
        let host = NSTextField(labelWithString: url.isFileURL ? url.lastPathComponent : url.host ?? url.absoluteString)
        host.font = .systemFont(ofSize: 13, weight: .semibold)
        host.lineBreakMode = .byTruncatingTail
        host.frame = NSRect(x: 16, y: height - 26, width: Metric.width - 32, height: 17)
        content.addSubview(host)

        var rest = url.isFileURL
            ? (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
            : url.path
        if let query = url.query { rest += "?" + query }
        let detail = NSTextField(labelWithString: rest.isEmpty ? url.scheme ?? "" : rest)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.frame = NSRect(x: 16, y: height - 43, width: Metric.width - 32, height: 15)
        content.addSubview(detail)

        for (index, choice) in choices.enumerated() {
            let row = RowView(choice: choice)
            row.frame.origin = NSPoint(x: 0, y: height - Metric.header - CGFloat(index + 1) * Metric.row)
            row.onHover = { [weak self] in self?.hover(index) }
            row.onActivate = { [weak self] in self?.choose(index, via: "click") }
            content.addSubview(row)
            rows.append(row)
        }
        select(highlight)

        panel.setFrameTopLeftPoint(anchor(height: height))
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                          object: panel, queue: .main) { [weak self] _ in
            self?.close(nil, via: "away")
        }
    }

    /// Open under the pointer, kept fully on the screen the pointer is on.
    private func anchor(height: CGFloat) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = mouse.x - Metric.width / 2
        var y = mouse.y + 12
        x = min(max(x, visible.minX + 12), visible.maxX - Metric.width - 12)
        y = min(max(y, visible.minY + height + 12), visible.maxY - 12)
        return NSPoint(x: x, y: y)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
        startCountdown()
    }

    /// Opens the highlighted row when it runs out. Anything you do first stops it and
    /// leaves the panel waiting, as it did before there was a countdown.
    private func startCountdown() {
        guard countdown > 0, rows.indices.contains(selected) else { return }
        let start = Date()
        rows[selected].progress = 1
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let left = 1 - Date().timeIntervalSince(start) / self.countdown
            if left <= 0 {
                self.choose(self.selected, via: "timer")
            } else {
                self.rows[self.selected].progress = CGFloat(left)
            }
        }
        // Common modes, so it keeps draining while the pointer moves over the panel.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopCountdown() {
        timer?.invalidate()
        timer = nil
        rows.forEach { $0.progress = nil }
    }

    private func hover(_ index: Int) {
        guard NSEvent.mouseLocation != pointer, index != selected else { return }
        stopCountdown()
        select(index)
    }

    private func select(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        rows[selected].isSelected = false
        selected = index
        rows[index].isSelected = true
    }

    private func choose(_ index: Int, via: String) {
        guard choices.indices.contains(index) else { return }
        close(choices[index], via: via)
    }

    private func close(_ choice: Choice?, via: String) {
        guard panel != nil else { return }
        stopCountdown()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        panel.orderOut(nil)
        panel = nil
        finish(choice, via)
    }

    private func handle(_ event: NSEvent) -> Bool {
        stopCountdown()
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            close(nil, via: "copy")
            return true
        }
        switch event.keyCode {
        case 53:
            close(nil, via: "escape")
            return true
        case 36, 76:
            choose(selected, via: "return")
            return true
        case 125, 121:
            select(min(selected + 1, rows.count - 1))
            return true
        case 126, 116:
            select(max(selected - 1, 0))
            return true
        default:
            break
        }
        guard let typed = event.charactersIgnoringModifiers?.lowercased(),
              let index = choices.firstIndex(where: { $0.key == typed })
        else { return false }
        select(index)
        choose(index, via: "key")
        return true
    }
}
