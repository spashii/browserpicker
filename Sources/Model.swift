import Foundation

/// What the model reads from one link.
struct Clues {
    /// Parts of the URL and the app it came from.
    let features: [String]
    /// Where the link lives, most specific first: host plus path, the host, then each
    /// enclosing domain. Level 0 is the host or deeper, level 1 an enclosing domain.
    let places: [(key: String, level: Int)]

    init(_ url: URL, source: String?) {
        var features = ["bias"]
        var places: [(key: String, level: Int)] = []
        if let source { features.append("app:" + source) }

        if let host = url.host?.lowercased() {
            let site = url.port.map { "\(host):\($0)" } ?? host
            // Shared hosts keep the identity in the path: github.com/<org>,
            // app.slack.com/client/<team>. Two segments reach both.
            let segments = url.path.split(separator: "/").prefix(2).map { $0.lowercased() }
            var prefix = site
            var paths: [String] = []
            for segment in segments {
                prefix += "/" + segment
                paths.append("path:" + prefix)
            }
            places += paths.reversed().map { ($0, 0) }
            places.append(("site:" + site, 0))

            // Enclosing domains, so a pick on staging.acme.dev says something about
            // app.acme.dev. Stops above the last label: "dev" or "com" alone means nothing.
            let labels = host.split(separator: ".").map(String.init)
            if labels.count > 2 {
                for start in 1..<(labels.count - 1) {
                    places.append(("host:" + labels[start...].joined(separator: "."), 1))
                }
            }
            features += places.map(\.key)

            // Loose words, so "acme" counts in any host or path with no shared prefix.
            let words = (labels.dropLast() + segments)
                .flatMap { $0.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) }
                .map(String.init)
                .filter { $0.count > 2 && $0 != "www" }
            features += Set(words).sorted().map { "word:" + $0 }
        }
        self.features = features
        self.places = places
    }
}

/// Softmax regression over the clues in a link, plus one learned nudge toward whatever
/// you picked last at the most specific place it shares with an earlier link. A few
/// thousand numbers at most, rebuilt from the log on every link, so it ships as code and
/// never as a file that could drift from the log.
struct Model {
    static let rate = 0.5
    static let trustRate = 0.1
    /// Below this the panel falls back to the configured default.
    static let sure = 0.6
    /// Old picks still count through the weights they left; this only bounds the replay.
    static let window = 2000

    let classes: [String]
    let rate: Double
    private var weights: [String: [Double]] = [:]
    /// The target picked most recently at each place.
    private var latest: [String: Int] = [:]
    /// How hard the latest pick at a place pushes its target, for a match on the host or
    /// deeper and for a match on an enclosing domain. They start high, so the first picks
    /// behave like "open it where I opened it last", then learn how often that holds.
    private(set) var trust: [Double]

    init(classes: [String], rate: Double = Model.rate, trust: [Double] = [2, 1]) {
        self.classes = classes
        self.rate = rate
        self.trust = trust
    }

    /// Replays the log in order, so it ends where an always-running learner would.
    /// A timed open that you redid in another target within a minute was a wrong
    /// guess, not a choice, so it teaches nothing. Links are compared trimmed, the way the
    /// log keeps them, so a whole link from an old log matches its trimmed redo; any other
    /// link the model cannot tell apart from it counts as a redo too.
    static func trained(on picks: [Pick], classes: [String]) -> Model {
        var model = Model(classes: classes)
        let opened = Array(picks.suffix(window))
        let places = opened.map { pick in URL(string: pick.url).flatMap(PickLog.trim) ?? pick.url }
        for (index, pick) in opened.enumerated() {
            guard let url = URL(string: pick.url) else { continue }
            if pick.via == "timer",
               opened.indices[(index + 1)...]
                   .prefix(while: { opened[$0].time.timeIntervalSince(pick.time) < 60 })
                   .contains(where: { places[$0] == places[index] && opened[$0].target != pick.target }) {
                continue
            }
            model.learn(Clues(url, source: pick.source), target: pick.target)
        }
        return model
    }

    mutating func learn(_ clues: Clues, target: String) {
        guard let truth = classes.firstIndex(of: target) else { return }
        let p = probabilities(clues)
        for feature in clues.features {
            var w = weights[feature] ?? Array(repeating: 0, count: classes.count)
            for k in classes.indices {
                w[k] += rate * ((k == truth ? 1 : 0) - p[k])
            }
            weights[feature] = w
        }
        if let last = recall(clues) {
            trust[last.level] += Model.trustRate * ((last.target == truth ? 1 : 0) - p[last.target])
        }
        for place in clues.places { latest[place.key] = truth }
    }

    /// Probability per target id.
    func predict(_ clues: Clues) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: zip(classes, probabilities(clues)))
    }

    private func recall(_ clues: Clues) -> (target: Int, level: Int)? {
        for place in clues.places {
            if let target = latest[place.key] { return (target, place.level) }
        }
        return nil
    }

    private func probabilities(_ clues: Clues) -> [Double] {
        var logits = Array(repeating: 0.0, count: classes.count)
        for feature in clues.features {
            guard let w = weights[feature] else { continue }
            for k in classes.indices { logits[k] += w[k] }
        }
        if let last = recall(clues) { logits[last.target] += trust[last.level] }
        let top = logits.max() ?? 0
        let e = logits.map { exp($0 - top) }
        let sum = e.reduce(0, +)
        return e.map { $0 / sum }
    }
}
