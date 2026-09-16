import AppKit

enum Launcher {
    /// Chromium only honours --profile-directory on a fresh process, so profile targets go
    /// through `open -n`: the new process hands the URL to the running browser, which opens
    /// it in the named profile. Everything else takes the plain path.
    static func open(_ url: URL, in target: Target) {
        var arguments: [String]
        if let profile = target.profileDirectory {
            arguments = ["-n", "-a", target.appURL.path, "--args",
                         "--profile-directory=\(profile)", url.absoluteString]
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
