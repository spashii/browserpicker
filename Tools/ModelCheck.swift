import Foundation

// Checks the guessing model and its log outside the app. Not part of the build.
//
//   swiftc -parse-as-library Sources/Model.swift Sources/PickLog.swift Tools/ModelCheck.swift -o /tmp/model-check
//   /tmp/model-check                                  # behaviour cases and the log format, exits 1 on a failure
//   /tmp/model-check replay picks.jsonl <default id>  # how often the highlight was right
//   /tmp/model-check log picks.jsonl                  # a real log against the one-time rewrite, on a copy
//
// The replay is the test that matters: it walks a real log in order and counts how often
// the countdown would have opened the wrong target. `log` never writes to the file it is
// given: it rewrites a copy in a temporary folder, checks the model learns the same, and
// runs the backup paths on that copy.

@main
enum ModelCheck {
    static func main() {
        let args = CommandLine.arguments
        if args.count >= 4, args[1] == "replay" {
            replay(path: args[2], fallback: args[3])
        } else if args.count >= 3, args[1] == "log" {
            exit(log(path: args[2]) ? 0 : 1)
        } else {
            let behaviour = cases()
            let format = logFormat()
            let files = logFiles()
            exit(behaviour && format && files ? 0 : 1)
        }
    }

    static let d = "com.brave.Browser#Default"
    static let k = "com.brave.Browser#Profile 1"
    static let s = "com.brave.Browser#Profile 2"
    static let all = [d, k, s, "com.brave.Browser#Profile 3", "com.apple.Safari"]

    static func pick(_ url: String, _ target: String, via: String = "key", at seconds: Double = 0) -> Pick {
        Pick(time: Date(timeIntervalSince1970: seconds), url: url, source: nil, target: target, via: via)
    }

    static func guess(_ picks: [Pick], _ url: String) -> (String, Double) {
        let model = Model.trained(on: picks, classes: all)
        let p = model.predict(Clues(URL(string: url)!, source: nil))
        let best = p.max { $0.value < $1.value }!
        return (best.key, best.value)
    }

    static func cases() -> Bool {
        var ok = true
        func expect(_ name: String, _ picks: [Pick], _ url: String, _ target: String?, sure: Bool?) {
            let (top, confidence) = guess(picks, url)
            let isSure = confidence >= Model.sure
            let pass = (sure == nil || isSure == sure) && (target == nil || top == target)
            ok = ok && pass
            print("\(pass ? "pass" : "FAIL")  \(name): \(top.split(separator: "#").last ?? "") \(String(format: "%.2f", confidence))")
        }

        expect("nothing learned yet", [], "https://example.com/", nil, sure: false)

        let acme = [pick("https://staging.acme.dev/", k)]
        expect("one pick, same host", acme, "https://staging.acme.dev/projects/4", k, sure: true)
        expect("one pick, unrelated host", acme, "https://news.ycombinator.com/", nil, sure: false)
        expect("one pick, sibling subdomain", acme, "https://app.acme.dev/", k, sure: true)
        expect("one pick, same word elsewhere", acme, "https://acme.slack.com/archives/C1", k, sure: nil)

        let orgs = [
            pick("https://github.com/initech/web/pull/1", d),
            pick("https://github.com/acme/web/issues/3", k),
            pick("https://github.com/initech/web/pull/2", d),
            pick("https://github.com/acme/web/pull/7", k),
        ]
        expect("shared host, org in the path", orgs, "https://github.com/initech/api/pull/9", d, sure: true)
        expect("shared host, other org", orgs, "https://github.com/acme/api", k, sure: true)
        expect("shared host, new org: last pick on the host", orgs, "https://github.com/apple/swift", k, sure: nil)

        let changed = Array(repeating: pick("https://calendar.google.com/", d), count: 5)
            + [pick("https://calendar.google.com/", s)]
        expect("last pick wins after a change", changed, "https://calendar.google.com/r/week", s, sure: true)

        let undone = [
            pick("https://linear.app/x", d),
            pick("https://linear.app/x", d, via: "timer", at: 100),
            pick("https://linear.app/x", k, at: 110),
        ]
        expect("redone timer pick is not learned", undone, "https://linear.app/x", k, sure: true)

        // The redo rule, exactly: a skipped timer pick leaves the model as if it never happened.
        func same(_ a: Model, _ b: Model, _ url: String) -> Bool {
            let clues = Clues(URL(string: url)!, source: nil)
            return a.predict(clues) == b.predict(clues)
        }
        func redo(_ name: String, timer: String, redo: String, after seconds: Double, skipped: Bool) {
            let timed = pick(timer, d, via: "timer", at: 100)
            let chosen = pick(redo, k, at: 100 + seconds)
            let with = Model.trained(on: [timed, chosen], classes: all)
            let without = Model.trained(on: [chosen], classes: all)
            let pass = same(with, without, timer) == skipped
            ok = ok && pass
            print("\(pass ? "pass" : "FAIL")  redo rule, \(name): \(skipped ? "skipped" : "learned")")
        }
        let full = "https://linear.app/acme/issue/ACM-12?focus=comment#c3"
        let short = PickLog.trim(URL(string: full)!)!
        redo("same whole link", timer: full, redo: full, after: 10, skipped: true)
        redo("same trimmed link", timer: short, redo: short, after: 10, skipped: true)
        redo("whole link from an old log, trimmed redo", timer: full, redo: short, after: 10, skipped: true)
        redo("other link, same place", timer: short, redo: "https://linear.app/acme/issue", after: 10, skipped: true)
        redo("other place", timer: short, redo: "https://linear.app/initech/issue", after: 10, skipped: false)
        redo("after a minute", timer: short, redo: short, after: 61, skipped: false)

        return ok
    }

    /// A log written before 0.5.0: whole links, guess and confidence, and lines with no target.
    static let oldLog = """
    {"confidence":0.40460967519168967,"guess":"\(d)","source":"com.tinyspeck.slackmacgap","target":"\(k)","time":"2026-11-04T11:15:43Z","url":"https://github.com/acme/web/pull/7?w=1#r9","via":"key"}
    {"confidence":0.9,"guess":"\(d)","source":"com.apple.mail","time":"2026-11-04T11:16:00Z","url":"https://example.com/private/token/abc","via":"escape"}
    {"guess":"\(d)","target":"\(d)","time":"2026-11-04T11:17:00Z","url":"https://calendar.google.com/calendar/u/0/r/week","via":"timer"}
    not json

    """

    /// The log keeps only what the model reads, and old logs still read.
    static func logFormat() -> Bool {
        var ok = true
        func check(_ name: String, _ pass: Bool) {
            ok = ok && pass
            print("\(pass ? "pass" : "FAIL")  \(name)")
        }

        // Every part of a link the trim drops or rewrites, with Clues compared on each.
        let links = [
            "https://github.com/acme/web/pull/7/files?diff=split#r123",
            "https://GitHub.com/Acme/Web",
            "https://user:secret@staging.acme.dev:8443/projects/4/settings?tab=1",
            "https://app.slack.com/client/T0123/C0456",
            "https://example.com",
            "https://example.com/",
            "https://example.com/one/",
            "https://example.com//double//slash/x",
            "https://example.com/a%2Fb/c/d",
            "https://example.com/%2F/a/b/c",
            "https://example.com/caf%C3%A9/men%C3%BC/x",
            "https://example.com/a;b=c/d/e",
            "https://example.com/a%3Bb/d/e",
            "https://example.com/100%25/x/y",
            "https://example.com/a+b/c d".addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)!,
            "https://xn--bcher-kva.example/b%C3%BCcher/x/y",
            "https://192.168.1.10:3000/api/v1/items?id=5",
            "https://[::1]:8080/a/b/c",
            "http://localhost:8787/report/2026/index.html",
            "file:///Users/someone/Downloads/page.html",
        ]
        for link in links {
            let url = URL(string: link)!
            guard let short = PickLog.trim(url), let back = URL(string: short) else {
                check("trim \(link): does not parse back", false)
                continue
            }
            let a = Clues(url, source: "com.tinyspeck.slackmacgap")
            let b = Clues(back, source: "com.tinyspeck.slackmacgap")
            let sameClues = a == b
            let idempotent = PickLog.trim(back) == short
            let bare = back.query == nil && back.fragment == nil && back.user == nil && back.password == nil
                && back.path.split(separator: "/").count <= 2
            check("trim \(link) -> \(short): same clues \(sameClues), twice the same \(idempotent), bare \(bare)",
                  sameClues && idempotent && bare)
        }

        let old = oldLog
        let read = PickLog.read(old)
        check("old log reads: 2 picks that opened, of 4 lines", read.count == 2 && read.map(\.target) == [k, d])
        let rewritten = PickLog.minimised(old)
        let lines = rewritten.split(separator: "\n")
        let fields = lines.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        check("rewrite keeps the 2 opened picks", lines.count == 2 && fields.count == 2)
        check("rewrite keeps time, url, source, target, via and nothing else",
              fields.allSatisfy { Set($0.keys).isSubset(of: ["time", "url", "source", "target", "via"]) }
              && Set(fields[0].keys) == ["time", "url", "source", "target", "via"]
              && Set(fields[1].keys) == ["time", "url", "target", "via"])
        check("rewrite trims the links",
              fields.map { $0["url"] as? String ?? "" } == ["https://github.com/acme/web", "https://calendar.google.com/calendar/u"])
        check("rewrite keeps time, source, target and via as they were",
              zip(read, PickLog.read(rewritten)).allSatisfy { $0.time == $1.time && $0.source == $1.source && $0.target == $1.target && $0.via == $1.via })
        check("rewrite of a rewritten log changes nothing", PickLog.minimised(rewritten) == rewritten)
        check("a new pick is written the same way",
              PickLog.encode(pick("https://github.com/acme/web/pull/7?w=1#r9", k)).map { String(decoding: $0, as: UTF8.self) }
                  == #"{"target":"com.brave.Browser#Profile 1","time":"1970-01-01T00:00:00Z","url":"https://github.com/acme/web","via":"key"}"# + "\n")
        return ok
    }

    /// The one-time rewrite and the backup cleanup on the synthetic old log.
    static func logFiles() -> Bool {
        var ok = true
        _ = rewritePaths(Data(oldLog.utf8)) { name, pass in
            ok = ok && pass
            print("\(pass ? "pass" : "FAIL")  \(name)")
        }
        return ok
    }

    /// Runs the rewrite and the backup cleanup on a copy of `original`, a log from before 0.5.0,
    /// in a temporary folder, and returns the rewritten log.
    static func rewritePaths(_ original: Data, _ check: (String, Bool) -> Void) -> String {
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent("model-check-\(UUID().uuidString)")
        try! files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: folder) }
        let log = folder.appendingPathComponent("picks.jsonl")
        let text = String(decoding: original, as: UTF8.self)
        func backups() -> [URL] {
            ((try? files.contentsOfDirectory(atPath: folder.path)) ?? [])
                .filter { $0.hasPrefix("picks.jsonl.bak-") }.sorted().map { folder.appendingPathComponent($0) }
        }
        func contents(_ url: URL) -> Data? { try? Data(contentsOf: url) }
        func reset() {
            backups().forEach { try? files.removeItem(at: $0) }
            try! original.write(to: log)
        }

        // A rewrite that does not check out puts the old log back and keeps the backup.
        let broken: [(String, (String) -> String)] = [
            ("loses a pick", { text in
                PickLog.minimised(text).split(separator: "\n").dropLast().map { $0 + "\n" }.joined() }),
            ("changes the clues", { text in
                PickLog.read(text).compactMap { pick -> Data? in
                    var pick = pick
                    if let url = URL(string: pick.url), let scheme = url.scheme, let host = url.host {
                        pick.url = "\(scheme)://\(host)/"
                    }
                    return PickLog.encode(pick)
                }.map { String(decoding: $0, as: UTF8.self) }.joined() }),
        ]
        for (name, rewrite) in broken {
            reset()
            let threw = (try? PickLog.minimise(log, rewrite: rewrite)) == nil
            check("a rewrite that \(name) throws, puts the old log back and keeps the backup",
                  threw && contents(log) == original && backups().count == 1 && contents(backups()[0]) == original)
        }

        // The rewrite as it ships: checked, then its backup goes.
        reset()
        let changed = (try? PickLog.minimise(log)) == true
        let rewritten = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        check("the rewrite checks out and removes its own backup",
              changed && PickLog.keeps(text, in: rewritten) && backups().isEmpty)
        check("no temporary file left", !files.fileExists(atPath: log.path + ".tmp"))
        check("a second rewrite changes nothing",
              (try? PickLog.minimise(log)) == false && contents(log) == Data(rewritten.utf8) && backups().isEmpty)

        // Backups 0.5.0 left behind.
        let other = folder.appendingPathComponent("config.json.bak-20261104")
        try! Data("{}".utf8).write(to: other)
        for stamp in ["20261109-193000", "20261110-080000"] {
            try! original.write(to: folder.appendingPathComponent("picks.jsonl.bak-" + stamp))
        }
        check("with the log trimmed, 0.5.0's backups go and nothing else does",
              PickLog.removeBackups(of: log) == 2 && backups().isEmpty && files.fileExists(atPath: other.path)
              && contents(log) == Data(rewritten.utf8))
        try! original.write(to: folder.appendingPathComponent("picks.jsonl.bak-20261109-193000"))
        try! original.write(to: log)
        check("with the log not yet trimmed, the backup stays",
              PickLog.removeBackups(of: log) == 0 && backups().count == 1 && contents(log) == original)
        try! files.removeItem(at: log)
        check("with no log, the backup stays", PickLog.removeBackups(of: log) == 0 && backups().count == 1)
        return rewritten
    }

    /// A real log, as a 0.4.0 or 0.5.0 build wrote it, against the one-time rewrite. Works on a
    /// copy in a temporary folder: the rewrite must keep every opened pick, give each the same
    /// clues, keep the model's guesses, back the old log up, and be a no-op the second time.
    static func log(path: String) -> Bool {
        var ok = true
        func check(_ name: String, _ pass: Bool) {
            ok = ok && pass
            print("\(pass ? "pass" : "FAIL")  \(name)")
        }
        guard let original = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let text = String(data: original, encoding: .utf8) else {
            print("cannot read \(path)")
            return false
        }
        let lines = text.split(separator: "\n")
        let before = PickLog.read(text)
        print("\(lines.count) lines, \(before.count) read as picks that opened")

        let rewritten = rewritePaths(original, check)
        let after = PickLog.read(rewritten)
        check("same number of picks: \(before.count) before, \(after.count) after, \(rewritten.split(separator: "\n").count) lines",
              before.count == after.count && rewritten.split(separator: "\n").count == after.count)

        let fields = rewritten.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        check("every line holds time, url, source, target, via and nothing else",
              fields.count == after.count && fields.allSatisfy {
                  Set($0.keys).subtracting(["source"]) == ["time", "url", "target", "via"] && Set($0.keys).count <= 5
              })
        check("every url is scheme://host[:port]/seg1/seg2",
              after.allSatisfy { pick in
                  let url = URL(string: pick.url)
                  return url != nil && url!.query == nil && url!.fragment == nil && url!.user == nil
                      && url!.path.split(separator: "/").count <= 2
              })
        check("time, source, target and via unchanged",
              zip(before, after).allSatisfy { $0.time == $1.time && $0.source == $1.source && $0.target == $1.target && $0.via == $1.via })
        check("same clues for every line", zip(before, after).allSatisfy { a, b in
            let x = Clues(URL(string: a.url)!, source: a.source)
            let y = Clues(URL(string: b.url)!, source: b.source)
            return x == y
        })

        // The guess the panel would have made before each pick, from the picks before it, with
        // more targets on offer than the log has seen.
        let classes = Array(Set(before.map(\.target) + all)).sorted()
        var sameGuesses = true
        for index in 0...before.count {
            let x = Model.trained(on: Array(before[..<index]), classes: classes)
            let y = Model.trained(on: Array(after[..<index]), classes: classes)
            let probes = index < before.count
                ? [(before[index], after[index])]
                : zip(before, after).map { ($0, $1) }
            for (a, b) in probes {
                let p = x.predict(Clues(URL(string: a.url)!, source: a.source))
                let q = y.predict(Clues(URL(string: b.url)!, source: b.source))
                if p != q { sameGuesses = false }
            }
        }
        check("the model gives the same guesses, to the last digit, before and after", sameGuesses)

        return ok
    }

    static func replay(path: String, fallback: String) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("cannot read \(path)")
            exit(1)
        }
        let picks = PickLog.read(text)
        let classes = Array(Set(picks.map(\.target) + [fallback])).sorted()
        print("\(picks.count) picks, \(classes.count) targets")

        var byHost: [String: String] = [:]
        var hostRight = 0
        var defaultRight = 0
        for pick in picks {
            let host = URL(string: pick.url)?.host ?? ""
            if (byHost[host] ?? fallback) == pick.target { hostRight += 1 }
            if fallback == pick.target { defaultRight += 1 }
            byHost[host] = pick.target
        }
        var latest: [String: String] = [:]
        var placeRight = 0
        for pick in picks {
            let places = Clues(URL(string: pick.url)!, source: nil).places.map(\.key)
            let recalled = places.lazy.compactMap { latest[$0] }.first
            if (recalled ?? fallback) == pick.target { placeRight += 1 }
            for place in places { latest[place] = pick.target }
        }
        print(String(format: "baseline  always default %.0f%%   last pick on the same host %.0f%%   last pick, hierarchical %.0f%%",
                     100 * Double(defaultRight) / Double(picks.count),
                     100 * Double(hostRight) / Double(picks.count),
                     100 * Double(placeRight) / Double(picks.count)))

        print("rate  trust   sure   right  sure%  sure-wrong  learned trust")
        for rate in [0.25, 0.5, 1.0] {
          for trust in [[1.0, 0.5], [2.0, 1.0], [3.0, 1.5]] {
            for sure in [0.5, 0.6, 0.7] {
                var model = Model(classes: classes, rate: rate, trust: trust)
                var right = 0, confident = 0, confidentWrong = 0
                for pick in picks {
                    let features = Clues(URL(string: pick.url)!, source: pick.source)
                    let best = model.predict(features).max { $0.value < $1.value }!
                    let highlight = best.value >= sure ? best.key : fallback
                    if highlight == pick.target { right += 1 }
                    if best.value >= sure {
                        confident += 1
                        if best.key != pick.target { confidentWrong += 1 }
                    }
                    model.learn(features, target: pick.target)
                }
                print(String(format: "%.2f  %.0f/%.1f   %.1f   %3.0f%%   %3.0f%%   %3d         %.2f/%.2f",
                             rate, trust[0], trust[1], sure, 100 * Double(right) / Double(picks.count),
                             100 * Double(confident) / Double(picks.count), confidentWrong,
                             model.trust[0], model.trust[1]))
            }
          }
        }
    }
}
