import AppKit
import SQLite3

/// A place a link can be sent: an app, optionally one profile inside it.
struct Target: Identifiable {
    let id: String
    let appURL: URL
    let bundleID: String
    let appName: String
    let profileName: String?
    /// Arguments that make a fresh process of the app open the link in this profile.
    let profileArguments: [String]

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

/// Firefox keeps its profiles in profiles.ini, or since the profile switcher in a
/// "Profile Groups" database, and accepts --profile <path> on launch.
private struct FirefoxFamily {
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

    private static let firefox: [FirefoxFamily] = [
        .init(bundleID: "org.mozilla.firefox", supportPath: "Firefox"),
    ]

    /// Browsers with no profile flag we can drive, plus anything chromium that hides its profiles.
    private static let single: [String] = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
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
                                    appName: name, profileName: nil, profileArguments: []))
            } else {
                for profile in profiles {
                    found.append(Target(id: "\(family.bundleID)#\(profile.directory)", appURL: appURL,
                                        bundleID: family.bundleID, appName: name, profileName: profile.name,
                                        profileArguments: ["--profile-directory=\(profile.directory)"]))
                }
            }
        }

        for family in firefox where family.bundleID != ourBundle {
            guard let appURL = appURL(family.bundleID) else { continue }
            let name = displayName(appURL)
            let profiles = firefoxProfiles(family.supportPath)
            if profiles.count < 2 {
                found.append(Target(id: family.bundleID, appURL: appURL, bundleID: family.bundleID,
                                    appName: name, profileName: nil, profileArguments: []))
            } else {
                for profile in profiles {
                    found.append(Target(id: "\(family.bundleID)#\(profile.directory)", appURL: appURL,
                                        bundleID: family.bundleID, appName: name, profileName: profile.name,
                                        profileArguments: ["--profile", profile.path]))
                }
            }
        }

        for bundleID in single where bundleID != ourBundle {
            guard let appURL = appURL(bundleID) else { continue }
            found.append(Target(id: bundleID, appURL: appURL, bundleID: bundleID,
                                appName: displayName(appURL), profileName: nil, profileArguments: []))
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
        var path: String = ""
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

    /// The profile switcher stores its profiles in a database named after the StoreID in
    /// profiles.ini, and profiles.ini then lists only one of them. Without it, profiles.ini
    /// is the whole list.
    private static func firefoxProfiles(_ supportPath: String) -> [Profile] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(supportPath)
        guard let ini = try? String(contentsOf: root.appendingPathComponent("profiles.ini"), encoding: .utf8)
        else { return [] }
        let sections = iniSections(ini).filter { $0.name.hasPrefix("Profile") }

        var entries: [(path: String, name: String)] = []
        if let storeID = sections.lazy.compactMap({ $0.values["StoreID"] }).first {
            entries = profileGroup(root.appendingPathComponent("Profile Groups/\(storeID).sqlite"))
        }
        if entries.isEmpty {
            entries = sections.compactMap { section in
                guard let path = section.values["Path"], let name = section.values["Name"] else { return nil }
                return (path, name)
            }
        }

        return entries.compactMap { entry in
            let url = entry.path.hasPrefix("/") ? URL(fileURLWithPath: entry.path)
                                                : root.appendingPathComponent(entry.path)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return Profile(directory: url.lastPathComponent, name: entry.name, path: url.path)
        }
    }

    private static func profileGroup(_ url: URL) -> [(path: String, name: String)] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT path, name FROM Profiles ORDER BY id", -1, &statement, nil) == SQLITE_OK
        else { return [] }

        var rows: [(path: String, name: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let path = sqlite3_column_text(statement, 0), let name = sqlite3_column_text(statement, 1)
            else { continue }
            rows.append((String(cString: path), String(cString: name)))
        }
        return rows
    }

    private static func iniSections(_ text: String) -> [(name: String, values: [String: String])] {
        var sections: [(name: String, values: [String: String])] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                sections.append((String(line.dropFirst().dropLast()), [:]))
            } else if let equals = line.firstIndex(of: "="), !sections.isEmpty {
                let key = String(line[..<equals])
                sections[sections.count - 1].values[key] = String(line[line.index(after: equals)...])
            }
        }
        return sections
    }
}
