import AppKit

enum Launcher {
    /// Chromium and Firefox only honour their profile flag on a fresh process, so profile
    /// targets go through `open -n`: the new process hands the URL to the browser already
    /// running that profile, or becomes it. Everything else takes the plain path.
    static func open(_ url: URL, in target: Target) {
        var arguments: [String]
        if !target.profileArguments.isEmpty {
            arguments = ["-n", "-a", target.appURL.path, "--args"] + target.profileArguments + [url.absoluteString]
        } else {
            arguments = ["-a", target.appURL.path, url.absoluteString]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            NSSound.beep()
        }
    }
}
