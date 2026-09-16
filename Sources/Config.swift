import Foundation

struct TargetSetting: Codable {
    var id: String
    var name: String?
    var key: String?
    var hidden: Bool?
}

struct Rule: Codable {
    var host: String
    var target: String
}

struct Config: Codable {
    var targets: [TargetSetting]
    var rules: [Rule]

    static let empty = Config(targets: [], rules: [])
}

/// One row in the picker: a discovered target dressed in the user's settings.
struct Choice {
    let target: Target
    let name: String
    let key: String
}

enum Store {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/browserpicker")
    }

    static var configURL: URL { directory.appendingPathComponent("config.json") }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data)
        else { return .empty }
        return config
    }

    static func save(_ config: Config) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: configURL)
    }

    /// Discovered targets in the user's order, with the settings file filled in for anything new.
    static func choices() -> [Choice] {
        let discovered = Discovery.targets()
        let byID = Dictionary(uniqueKeysWithValues: discovered.map { ($0.id, $0) })
        var config = load()
        var settings = config.targets.filter { byID[$0.id] != nil }
        let known = Set(settings.map(\.id))
        for target in discovered where !known.contains(target.id) {
            let setting = TargetSetting(id: target.id, name: nil, key: nil, hidden: nil)
            // A new profile joins its app so the list stays grouped instead of growing at the tail.
            if let sibling = settings.lastIndex(where: { byID[$0.id]?.bundleID == target.bundleID }) {
                settings.insert(setting, at: sibling + 1)
            } else {
                settings.append(setting)
            }
        }

        var taken = Set(settings.compactMap { $0.key?.lowercased() })
        let pool = Array("123456789abcdefghijklmnopqrstuvwxyz").map(String.init)
        var choices: [Choice] = []
        for index in settings.indices {
            guard let target = byID[settings[index].id] else { continue }
            if settings[index].key == nil, settings[index].hidden != true {
                if let free = pool.first(where: { !taken.contains($0) }) {
                    settings[index].key = free
                    taken.insert(free)
                }
            }
            guard settings[index].hidden != true else { continue }
            choices.append(Choice(target: target,
                                  name: settings[index].name ?? target.defaultName,
                                  key: settings[index].key ?? ""))
        }

        if settings.map(\.id) != config.targets.map(\.id) || settings.contains(where: { $0.key != nil }) {
            config.targets = settings
            save(config)
        }
        return choices
    }

    /// A host rule wins over the picker. Longest suffix match, so a rule on one
    /// subdomain beats a rule on the parent domain.
    static func rule(for url: URL, in choices: [Choice]) -> Choice? {
        guard let host = url.host?.lowercased() else { return nil }
        let matches = load().rules.filter { rule in
            let pattern = rule.host.lowercased()
            return host == pattern || host.hasSuffix("." + pattern)
        }
        guard let best = matches.max(by: { $0.host.count < $1.host.count }) else { return nil }
        return choices.first { $0.target.id == best.target }
    }
}
