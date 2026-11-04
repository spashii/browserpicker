import Foundation

// Checks the guessing model outside the app. Not part of the build.
//
//   swiftc -parse-as-library Sources/Model.swift Tools/ModelCheck.swift -o /tmp/model-check
//   /tmp/model-check                                  # behaviour cases, exits 1 on a failure
//   /tmp/model-check replay picks.jsonl <default id>  # how often the highlight was right
//
// The replay is the test that matters: it walks a real log in order and counts how often
// the countdown would have opened the wrong target.

@main
enum ModelCheck {
    static func main() {
        let args = CommandLine.arguments
        if args.count >= 4, args[1] == "replay" {
            replay(path: args[2], fallback: args[3])
        } else {
            exit(cases() ? 0 : 1)
        }
    }

    static let d = "com.brave.Browser#Default"
    static let k = "com.brave.Browser#Profile 1"
    static let s = "com.brave.Browser#Profile 2"
    static let all = [d, k, s, "com.brave.Browser#Profile 3", "com.apple.Safari"]

    static func pick(_ url: String, _ target: String, via: String = "key", at seconds: Double = 0) -> Pick {
        Pick(time: Date(timeIntervalSince1970: seconds), url: url, source: nil, guess: nil,
             confidence: nil, target: target, via: via)
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

        return ok
    }

    static func replay(path: String, fallback: String) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("cannot read \(path)")
            exit(1)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let picks = text.split(separator: "\n").compactMap {
            try? decoder.decode(Pick.self, from: Data($0.utf8))
        }.filter { $0.target != nil }
        let classes = Array(Set(picks.compactMap(\.target) + [fallback])).sorted()
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
                    model.learn(features, target: pick.target!)
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
