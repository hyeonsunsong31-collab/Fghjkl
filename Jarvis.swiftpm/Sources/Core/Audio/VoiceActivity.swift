import Foundation

/// Energy-based voice-activity detector with an adaptive noise floor and
/// hangover, used for endpointing utterances and detecting barge-in.
struct VoiceActivityDetector {
    enum Event: Equatable { case speechStarted, speechEnded(duration: Double) }

    /// dB above the noise floor that counts as speech.
    var marginDB: Double = 11
    /// Absolute minimum level for speech (dBFS).
    var minimumDB: Double = -52
    /// Frames of speech required to trigger a start.
    var startFrames = 3
    /// Seconds of silence that end an utterance.
    var hangover: Double = 0.85
    /// Continuous "speech" longer than this is background sound (music, TV, a fan): it ends
    /// the utterance and becomes the new noise floor, so the detector can never get stuck.
    var maxSpeech: Double = 15

    private(set) var noiseFloorDB: Double = -60
    private(set) var isSpeaking = false
    private(set) var levelDB: Double = -100
    private var speechRun = 0
    private var silenceTime: Double = 0
    private var speechTime: Double = 0
    /// Smoothed level while speaking (used to learn sustained background sound).
    private var speechLevelDB: Double = -100

    /// RMS level of a block of samples in dBFS.
    static func level(_ samples: UnsafeBufferPointer<Float>) -> Double {
        guard !samples.isEmpty else { return -100 }
        var sum: Double = 0
        for s in samples { sum += Double(s) * Double(s) }
        let rms = (sum / Double(samples.count)).squareRoot()
        return 20 * log10(max(rms, 1e-7))
    }

    static func level(_ samples: [Float]) -> Double {
        samples.withUnsafeBufferPointer { level($0) }
    }

    /// Feed one block (its level in dBFS and duration in seconds).
    mutating func process(levelDB db: Double, duration: Double) -> Event? {
        levelDB = db
        let threshold = max(minimumDB, noiseFloorDB + marginDB)
        let voiced = db > threshold
        if !isSpeaking {
            // Track the noise floor only while not speaking (fast down, slow up).
            noiseFloorDB = db < noiseFloorDB ? noiseFloorDB * 0.7 + db * 0.3 : noiseFloorDB * 0.995 + db * 0.005
            if voiced {
                speechRun += 1
                if speechRun >= startFrames {
                    isSpeaking = true
                    silenceTime = 0
                    speechTime = Double(speechRun) * duration
                    speechLevelDB = db
                    return .speechStarted
                }
            } else {
                speechRun = 0
            }
            return nil
        }
        speechTime += duration
        speechLevelDB = speechLevelDB * 0.97 + db * 0.03
        if speechTime >= maxSpeech {
            // Nobody talks for this long without a pause: treat the sound as background.
            isSpeaking = false
            speechRun = 0
            silenceTime = 0
            noiseFloorDB = max(noiseFloorDB, speechLevelDB - 3)
            return .speechEnded(duration: speechTime)
        }
        if voiced {
            silenceTime = 0
        } else {
            silenceTime += duration
            if silenceTime >= hangover {
                isSpeaking = false
                speechRun = 0
                let d = speechTime - silenceTime
                return .speechEnded(duration: max(0, d))
            }
        }
        return nil
    }

    /// Normalised 0…1 level for UI meters.
    var meter: Float { Float(max(0, min(1, (levelDB + 60) / 50))) }
}
