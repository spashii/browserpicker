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
    /// Highlighted when the model is unsure. Falls back to the top row.
    var defaultTarget: String?
    /// Seconds before the highlighted row opens by itself. 0 turns it off.
    var countdown: Double?

    static let empty = Config(targets: [], rules: [])

    enum CodingKeys: String, CodingKey {
        case targets, rules, countdown
        case defaultTarget = "default"
    }
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
    static var picksURL: URL { directory.appendingPathComponent("picks.jsonl") }

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

    /// The row to highlight: the model's guess when it is sure, otherwise the
    /// configured default, otherwise the top row.
    static func guess(for url: URL, source: String?, in choices: [Choice]) -> (index: Int, confidence: Double?) {
        let config = load()
        let fallback = config.defaultTarget.flatMap { id in choices.firstIndex { $0.target.id == id } } ?? 0
        let log = picks()
        guard log.contains(where: { $0.target != nil }) else { return (fallback, nil) }

        let classes = Array(Set(choices.map(\.target.id) + log.compactMap(\.target))).sorted()
        let p = Model.trained(on: log, classes: classes).predict(Clues(url, source: source))
        guard let best = choices.indices.max(by: { p[choices[$0].target.id, default: 0] < p[choices[$1].target.id, default: 0] })
        else { return (fallback, nil) }
        let confidence = p[choices[best].target.id, default: 0]
        return (confidence >= Model.sure ? best : fallback, confidence)
    }

    static var countdown: Double { load().countdown ?? 5 }

    private static var cachedPicks: [Pick]?

    /// The log, read once per run and kept in step by record(_:).
    static func picks() -> [Pick] {
        if let cachedPicks { return cachedPicks }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let text = (try? String(contentsOf: picksURL, encoding: .utf8)) ?? ""
        let picks = text.split(separator: "\n").compactMap { try? decoder.decode(Pick.self, from: Data($0.utf8)) }
        cachedPicks = picks
        return picks
    }

    static func record(_ pick: Pick) {
        cachedPicks = picks() + [pick]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var line = try? encoder.encode(pick) else { return }
        line.append(0x0A)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: picksURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: picksURL)
        }
    }
}
