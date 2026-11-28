import Foundation

/// Task-duration estimates (requirement 2-(4)): combines the cerebellum's
/// learned prediction with per-intent history, and phrases the announcement.
struct TimeEstimator: Codable {
    /// Exponential moving average of observed durations per key (intent / tool).
    private(set) var history: [String: Double] = [:]
    var smoothing: Double = 0.3
    /// Only announce tasks expected to take at least this long.
    var announceThreshold: Double = 3

    static let defaults: [String: Double] = [
        "fastCommand": 0.2, "conversational": 2.5, "toolUse": 4, "clarify": 1.5, "deepThink": 12,
        "generateModel": 3, "refineModel": 2, "webSearch": 4, "playMusic": 3, "exportModel": 2, "openApp": 0.6
    ]

    mutating func record(key: String, seconds: Double) {
        let old = history[key] ?? seconds
        history[key] = old + (seconds - old) * smoothing
    }

    func estimate(key: String, cerebellar: Double?) -> Double {
        let hist = history[key] ?? Self.defaults[key]
        switch (hist, cerebellar) {
        case let (h?, c?): return 0.5 * h + 0.5 * c
        case let (h?, nil): return h
        case let (nil, c?): return c
        default: return 2
        }
    }

    func shouldAnnounce(_ seconds: Double) -> Bool { seconds >= announceThreshold }

    static func phrase(_ seconds: Double, language: DetectedLanguage) -> String {
        let s = max(1, Int(seconds.rounded()))
        if language == .korean {
            if s < 60 { return "약 \(s)초 정도 걸릴 예정입니다." }
            let m = Int((Double(s) / 60).rounded())
            return "약 \(m)분 정도 걸릴 예정입니다."
        }
        if s < 60 { return "This should take approximately \(s) second\(s == 1 ? "" : "s"), sir." }
        let m = Int((Double(s) / 60).rounded())
        return "This should take approximately \(m) minute\(m == 1 ? "" : "s"), sir."
    }
}
