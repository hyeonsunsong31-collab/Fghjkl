import Foundation

/// An episodic memory trace.
struct Episode: Codable, Identifiable, Equatable {
    var id: String
    var text: String
    var kind: String
    var timestamp: Date
    var importance: Float
    /// Pattern-separated dentate-gyrus code.
    var dgCode: [Int]
}

/// **Hippocampus** — fast episodic memory.
///
/// Dentate gyrus: sparse random expansion (2048 → 8192) with strong lateral
/// inhibition → pattern separation (similar inputs, distinct codes). CA3:
/// auto-associative completion via an inverted index over DG cells — a partial
/// cue retrieves the whole episode. CA1 returns the ranked episodes. Idle-time
/// replay feeds consolidation into the cortex.
final class Hippocampus {
    static let dgSize = 8192
    static let dgActive = 80

    let dentateGyrus: PerceptronPopulation
    private(set) var episodes: [Episode] = []
    private var index: [Int: [Int]] = [:] // DG cell → episode indices
    let capacity: Int

    init(seed: UInt64, capacity: Int = 4000) {
        self.capacity = capacity
        dentateGyrus = PerceptronPopulation(name: "hippocampus.DG",
                                            ids: RegionAllocator.ids(in: .dentateGyrus, count: Self.dgSize, seed: seed),
                                            inputSize: Cortex.inputSize, connectivity: .random(fanIn: 12),
                                            weightScale: 1.0, activation: .relu, rule: .none,
                                            kWinners: Self.dgActive, seed: seed &+ 1)
    }

    func separate(_ code: SparseCode) -> [Int] {
        let out = dentateGyrus.step(code.dense())
        return (0..<Self.dgSize).filter { out[$0] > 0 }
    }

    @discardableResult
    func encode(text: String, kind: String, importance: Float, code: SparseCode, at date: Date = Date()) -> Episode {
        let dg = separate(code)
        let episode = Episode(id: UUID().uuidString, text: text, kind: kind, timestamp: date,
                              importance: NeuroMath.clamp(importance, 0, 1), dgCode: dg)
        episodes.append(episode)
        if episodes.count > capacity { forgetLeastValuable() } else { indexEpisode(episodes.count - 1) }
        return episode
    }

    private func indexEpisode(_ i: Int) {
        for cell in episodes[i].dgCode { index[cell, default: []].append(i) }
    }

    private func rebuildIndex() {
        index.removeAll(keepingCapacity: true)
        for i in episodes.indices { indexEpisode(i) }
    }

    private func forgetLeastValuable() {
        let now = Date()
        let scored = episodes.enumerated().map { (i, e) -> (Int, Float) in
            let ageDays = Float(now.timeIntervalSince(e.timestamp) / 86_400)
            return (i, e.importance - 0.02 * ageDays)
        }
        if let worst = scored.min(by: { $0.1 < $1.1 })?.0 { episodes.remove(at: worst) }
        rebuildIndex()
    }

    /// Pattern completion: retrieve the `k` episodes that best match a cue.
    func recall(_ cue: SparseCode, k: Int = 5, now: Date = Date()) -> [(Episode, Float)] {
        let dg = separate(cue)
        var votes: [Int: Int] = [:]
        for cell in dg { for e in index[cell] ?? [] { votes[e, default: 0] += 1 } }
        let ranked = votes.map { (i, v) -> (Int, Float) in
            let e = episodes[i]
            let overlap = Float(v) / Float(Self.dgActive)
            let ageHours = Float(now.timeIntervalSince(e.timestamp) / 3600)
            let recency = 1 / (1 + ageHours / 48)
            return (i, overlap * 0.8 + e.importance * 0.1 + recency * 0.1)
        }
        .sorted { $0.1 > $1.1 }
        return ranked.prefix(k).map { (episodes[$0.0], $0.1) }
    }

    /// Episodes chosen for offline replay (most important, recent first).
    func replayCandidates(_ n: Int) -> [Episode] {
        Array(episodes.sorted { a, b in
            a.importance == b.importance ? a.timestamp > b.timestamp : a.importance > b.importance
        }.prefix(n))
    }

    func exportEpisodes() throws -> Data { try JSONEncoder().encode(episodes) }

    func importEpisodes(_ data: Data) throws {
        episodes = try JSONDecoder().decode([Episode].self, from: data)
        rebuildIndex()
    }

    func archive(into w: inout BinaryWriter) { dentateGyrus.archive(into: &w) }
    func restore(from r: inout BinaryReader) throws { try dentateGyrus.restore(from: &r) }
}
