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
    /// one and never half of either. Returns the backup, or nil when there was nothing to
    /// change. Throws, with the log as it was, when the backup or the write fails.
    @discardableResult
    static func minimise(_ file: URL, now: Date = Date()) throws -> URL? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let text = try String(contentsOf: file, encoding: .utf8)
        let minimal = minimised(text)
        guard minimal != text else { return nil }

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let folder = file.deletingLastPathComponent()
        let backup = folder.appendingPathComponent(file.lastPathComponent + ".bak-" + stamp.string(from: now))
        try FileManager.default.copyItem(at: file, to: backup)

        let temporary = folder.appendingPathComponent(file.lastPathComponent + ".tmp")
        try Data(minimal.utf8).write(to: temporary)
        guard rename(temporary.path, file.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
        return backup
    }
}
