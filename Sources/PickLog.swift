import Foundation

/// One line of picks.jsonl: a link that opened, and how. These are exactly the fields the
/// model reads, and the log keeps nothing else. The log is the model's only state, so
/// deleting the file starts it over from nothing.
struct Pick: Codable {
    var time: Date
    /// The link as PickLog.trim cuts it down.
    var url: String
    /// Bundle id of the app the link was clicked in, when macOS says.
    var source: String?
    /// The target that opened.
    var target: String
    /// key, click, return or timer. The model reads it to spot a timed open you redid.
    var via: String
}

extension Pick {
    /// A pick as the log keeps it. Nil for a link that does not parse, which the model
    /// could not learn from either.
    init?(time: Date, url: URL, source: String?, target: String, via: String) {
        guard let short = PickLog.trim(url) else { return nil }
        self.init(time: time, url: short, source: source, target: target, via: via)
    }
}

enum PickLog {
    /// scheme://host[:port]/seg1/seg2. Clues reads the host, the port, the first two path
    /// segments and the words in them, so that is all the log keeps of a link: no query,
    /// no fragment, no login and no deeper path. Clues of the trimmed link equal Clues of
    /// the full one, and trimming twice changes nothing.
    static func trim(_ url: URL) -> String? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        // Clues splits the decoded path, so the segments are taken the same way and encoded
        // again. "/" and ";" are encoded inside a segment so they cannot split it on the
        // way back in.
        let segments = url.path.split(separator: "/").prefix(2)
            .map { $0.addingPercentEncoding(withAllowedCharacters: segment) ?? "" }
        parts.user = nil
        parts.password = nil
        parts.query = nil
        parts.fragment = nil
        parts.percentEncodedPath = "/" + segments.joined(separator: "/")
        return parts.string
    }

    private static let segment = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/;"))

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Every line that reads as a pick, old or new. Lines from before 0.5.0 carry a whole
    /// link and `guess` and `confidence`, which decoding passes over; their lines for links
    /// that never opened have no target and are skipped, as the model always skipped them.
    static func read(_ text: String) -> [Pick] {
        text.split(separator: "\n").compactMap { try? decoder.decode(Pick.self, from: Data($0.utf8)) }
    }

    /// One line, newline included, with its link trimmed. Nil when the link does not parse.
    static func encode(_ pick: Pick) -> Data? {
        guard let url = URL(string: pick.url),
              let kept = Pick(time: pick.time, url: url, source: pick.source, target: pick.target, via: pick.via),
              var line = try? encoder.encode(kept)
        else { return nil }
        line.append(0x0A)
        return line
    }

    static func append(_ pick: Pick, to file: URL) {
        guard let line = encode(pick) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: file)
        }
    }

    /// The log as this version writes it. A log that already is comes back unchanged.
    static func minimised(_ text: String) -> String {
        read(text).compactMap(encode).map { String(decoding: $0, as: UTF8.self) }.joined()
    }

    /// Rewrites a log from before 0.5.0 the way this version writes it, so it holds only what
    /// the model reads. Copies the old log to `<name>.bak-<time>` first, then writes a
    /// temporary file and renames it over the log, so a crash leaves the old log or the new
    /// one and never half of either. The backup holds the whole old links the rewrite exists
    /// to drop, so it goes as soon as the new log checks out; when it does not, the old log
    /// comes back from the backup and the backup stays. Returns whether the log changed.
    /// `rewrite` is there for ModelCheck to break.
    @discardableResult
    static func minimise(_ file: URL, now: Date = Date(),
                         rewrite: (String) -> String = PickLog.minimised) throws -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        let text = try String(contentsOf: file, encoding: .utf8)
        let minimal = rewrite(text)
        guard minimal != text else { return false }

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let backup = file.deletingLastPathComponent()
            .appendingPathComponent(file.lastPathComponent + backupMark + stamp.string(from: now))
        try FileManager.default.copyItem(at: file, to: backup)
        try replace(file, with: Data(minimal.utf8))

        guard let written = try? String(contentsOf: file, encoding: .utf8), keeps(text, in: written) else {
            try replace(file, with: Data(contentsOf: backup))
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.removeItem(at: backup)
        return true
    }

    /// Whether `written` holds every pick of the `old` log the model could learn from, in order,
    /// each line parsing, with the same time, source, target and via and the same clues.
    static func keeps(_ old: String, in written: String) -> Bool {
        let expected = read(old).filter { URL(string: $0.url) != nil }
        let picks = read(written)
        guard picks.count == expected.count, written.split(separator: "\n").count == picks.count else { return false }
        return zip(expected, picks).allSatisfy { a, b in
            guard let x = URL(string: a.url), let y = URL(string: b.url) else { return false }
            return a.time == b.time && a.source == b.source && a.target == b.target && a.via == b.via
                && Clues(x, source: a.source) == Clues(y, source: b.source)
        }
    }

    /// Removes the `<name>.bak-*` backups next to the log, which 0.5.0 kept after its rewrite
    /// with the whole old links in them. Only once the log itself is in the trimmed shape, so
    /// a backup is never the last copy of picks the log does not hold yet. Returns the count.
    @discardableResult
    static func removeBackups(of file: URL) -> Int {
        guard let text = try? String(contentsOf: file, encoding: .utf8), minimised(text) == text else { return 0 }
        let folder = file.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix(file.lastPathComponent + backupMark) }.filter { name in
            (try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))) != nil
        }.count
    }

    private static let backupMark = ".bak-"

    /// A temporary file renamed over `file`, so readers see the old contents or the new.
    private static func replace(_ file: URL, with data: Data) throws {
        let temporary = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".tmp")
        try data.write(to: temporary)
        guard rename(temporary.path, file.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
