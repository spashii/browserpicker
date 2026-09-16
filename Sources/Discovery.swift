import AppKit

/// A place a link can be sent: an app, optionally one profile inside it.
struct Target: Identifiable {
    let id: String
    let appURL: URL
    let bundleID: String
    let appName: String
    let profileDirectory: String?
    let profileName: String?

    var defaultName: String {
        if let profileName { return "\(appName) · \(profileName)" }
        return appName
    }

    var icon: NSImage { NSWorkspace.shared.icon(forFile: appURL.path) }
}

/// Chromium browsers keep their profile list in a JSON file under Application Support
/// and accept --profile-directory on launch.
private struct ChromiumFamily {
    let bundleID: String
    let supportPath: String
}

enum Discovery {
    private static let chromium: [ChromiumFamily] = [
        .init(bundleID: "com.brave.Browser", supportPath: "BraveSoftware/Brave-Browser"),
        .init(bundleID: "com.brave.Browser.beta", supportPath: "BraveSoftware/Brave-Browser-Beta"),
        .init(bundleID: "com.brave.Browser.nightly", supportPath: "BraveSoftware/Brave-Browser-Nightly"),
        .init(bundleID: "com.google.Chrome", supportPath: "Google/Chrome"),
        .init(bundleID: "com.google.Chrome.beta", supportPath: "Google/Chrome Beta"),
        .init(bundleID: "com.google.Chrome.canary", supportPath: "Google/Chrome Canary"),
        .init(bundleID: "com.microsoft.edgemac", supportPath: "Microsoft Edge"),
        .init(bundleID: "com.vivaldi.Vivaldi", supportPath: "Vivaldi"),
        .init(bundleID: "org.chromium.Chromium", supportPath: "Chromium"),
    ]

    /// Browsers with no profile flag we can drive, plus anything chromium that hides its profiles.
    private static let single: [String] = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "app.zen-browser.zen",
        "com.kagi.kagimacOS",
        "company.thebrowser.Browser",
        "com.operasoftware.Opera",
        "net.waterfox.waterfox",
        "com.duckduckgo.macos.browser",
    ]

    static func targets() -> [Target] {
        var found: [Target] = []
        let ourBundle = Bundle.main.bundleIdentifier ?? ""

        for family in chromium where family.bundleID != ourBundle {
            guard let appURL = appURL(family.bundleID) else { continue }
            let name = displayName(appURL)
            let profiles = chromiumProfiles(family.supportPath)
            if profiles.isEmpty {
                found.append(Target(id: family.bundleID, appURL: appURL, bundleID: family.bundleID,
                                    appName: name, profileDirectory: nil, profileName: nil))
            } else {
                for profile in profiles {
                    found.append(Target(id: "\(family.bundleID)#\(profile.directory)", appURL: appURL,
                                        bundleID: family.bundleID, appName: name,
                                        profileDirectory: profile.directory, profileName: profile.name))
                }
            }
        }

        for bundleID in single where bundleID != ourBundle {
            guard let appURL = appURL(bundleID) else { continue }
            found.append(Target(id: bundleID, appURL: appURL, bundleID: bundleID,
                                appName: displayName(appURL), profileDirectory: nil, profileName: nil))
        }

        return found
    }

    private static func appURL(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private static func displayName(_ url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private struct Profile {
        let directory: String
        let name: String
    }

    private static func chromiumProfiles(_ supportPath: String) -> [Profile] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(supportPath)
        let stateURL = root.appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: stateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any]
        else { return [] }

        let order = profile["profiles_order"] as? [String] ?? []
        let directories = cache.keys.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? (a == "Default" ? -1 : Int.max)
            let ib = order.firstIndex(of: b) ?? (b == "Default" ? -1 : Int.max)
            if ia != ib { return ia < ib }
            return a < b
        }

        return directories.compactMap { directory in
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent(directory).path) else { return nil }
            let entry = cache[directory] as? [String: Any]
            let name = (entry?["name"] as? String) ?? directory
            return Profile(directory: directory, name: name)
        }
    }
}
