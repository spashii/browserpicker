import AppKit

enum Launcher {
    /// Chromium and Firefox only honour their profile flag on a fresh process, so profile
    /// targets go through `open -n`: the new process hands the URL to the browser already
    /// running that profile, or becomes it. Everything else takes the plain path.
    /// `done` runs on the main thread once `open` has handed the link over, or failed to.
    static func open(_ url: URL, in target: Target, done: @escaping () -> Void) {
        var arguments: [String]
        if !target.profileArguments.isEmpty {
            arguments = ["-n", "-a", target.appURL.path, "--args"] + target.profileArguments + [url.absoluteString]
        } else {
            arguments = ["-a", target.appURL.path, url.absoluteString]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        process.terminationHandler = { _ in DispatchQueue.main.async(execute: done) }
        do {
            try process.run()
        } catch {
            NSSound.beep()
            DispatchQueue.main.async(execute: done)
        }
    }
}
