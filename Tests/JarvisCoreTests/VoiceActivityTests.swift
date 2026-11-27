import XCTest
@testable import JarvisCore

final class VoiceActivityTests: XCTestCase {
    /// Feed `count` blocks of 20 ms at `db` dBFS and collect the events.
    private func feed(_ vad: inout VoiceActivityDetector, db: Double, count: Int) -> [VoiceActivityDetector.Event] {
        var events: [VoiceActivityDetector.Event] = []
        for _ in 0..<count {
            if let e = vad.process(levelDB: db, duration: 0.02) { events.append(e) }
        }
        return events
    }

    func testUtteranceStartsAndEnds() {
        var vad = VoiceActivityDetector()
        XCTAssertTrue(feed(&vad, db: -62, count: 50).isEmpty)
        XCTAssertEqual(feed(&vad, db: -24, count: 40), [.speechStarted])
        let end = feed(&vad, db: -62, count: 60)
        XCTAssertEqual(end.count, 1)
        if case .speechEnded(let d)? = end.first { XCTAssertEqual(d, 0.8, accuracy: 0.15) } else { XCTFail("no end") }
    }

    func testSustainedBackgroundSoundNeverKeepsItStuck() {
        var vad = VoiceActivityDetector()
        _ = feed(&vad, db: -62, count: 50)
        // 25 s of music at -30 dBFS: one "utterance", ended by the cap, then quiet.
        let events = feed(&vad, db: -30, count: 1250)
        XCTAssertEqual(events.first, .speechStarted)
        XCTAssertEqual(events.count, 2)
        if case .speechEnded(let d)? = events.last { XCTAssertEqual(d, vad.maxSpeech, accuracy: 0.1) } else { XCTFail("not ended") }
        XCTAssertFalse(vad.isSpeaking)
        // A voice clearly above the music is still heard, and its end is detected.
        XCTAssertEqual(feed(&vad, db: -12, count: 30), [.speechStarted])
        let end = feed(&vad, db: -30, count: 60)
        XCTAssertEqual(end.count, 1)
    }

    func testNoiseFloorRecoversWhenTheRoomGoesQuiet() {
        var vad = VoiceActivityDetector()
        _ = feed(&vad, db: -30, count: 1000)
        _ = feed(&vad, db: -65, count: 100)
        // Ordinary speech is detected again once the music has stopped.
        XCTAssertEqual(feed(&vad, db: -35, count: 20), [.speechStarted])
    }
}
