import XCTest
@testable import JarvisCore

final class VoiceGateTests: XCTestCase {
    func testAcceptsNormalSpeech() {
        let c = VoiceGate.Context()
        XCTAssertEqual(VoiceGate.utterance("open the 3D space", confidence: 0.9, context: c), .accept)
        XCTAssertEqual(VoiceGate.utterance("빨간 큐브 만들어줘", confidence: 0.8, context: c), .accept)
        XCTAssertEqual(VoiceGate.utterance("yes", confidence: 0.2, context: c), .accept)
        XCTAssertEqual(VoiceGate.utterance("네", confidence: 0.2, context: c), .accept)
    }

    func testDropsJarvisHearingItself() {
        var c = VoiceGate.Context()
        c.jarvisSpeaking = true
        c.spokenRecently = "I have created three red cubes, sir."
        XCTAssertEqual(VoiceGate.utterance("I have created three red cubes", confidence: 0.9, context: c), .drop("echo"))
        c.jarvisSpeaking = false
        c.secondsSinceSpeechEnded = 1.0
        c.spokenRecently = "Jarvis at your service, sir."
        XCTAssertEqual(VoiceGate.utterance("Jarvis at your service sir", confidence: 0.9, context: c), .drop("echo"))
    }

    func testWhileSpeaking() {
        var c = VoiceGate.Context()
        c.jarvisSpeaking = true
        c.spokenRecently = "The weather today is sunny with a light breeze."
        // A sentence unlike Jarvis' own is the user talking over it.
        XCTAssertEqual(VoiceGate.utterance("make a cube", confidence: 0.9, context: c), .accept)
        XCTAssertEqual(VoiceGate.utterance("빨간 큐브 만들어줘", confidence: 0.9, context: c), .accept)
        // Single words and sentences like Jarvis' own are its voice coming back.
        XCTAssertEqual(VoiceGate.utterance("cube", confidence: 0.9, context: c), .drop("while speaking"))
        XCTAssertEqual(VoiceGate.utterance("sunny breeze today", confidence: 0.9, context: c), .drop("echo"))
        c.spokenRecently = "I have created three red cubes, sir."
        XCTAssertEqual(VoiceGate.utterance("I have greeted tree rare cubes", confidence: 0.9, context: c), .drop("while speaking"))
        // Interruptions always get through.
        XCTAssertEqual(VoiceGate.utterance("stop", confidence: 0.9, context: c), .accept)
        XCTAssertEqual(VoiceGate.utterance("Jarvis make a cube", confidence: 0.9, context: c), .accept)
        XCTAssertEqual(VoiceGate.utterance("그만", confidence: 0.9, context: c), .accept)
    }

    func testRightAfterSpeech() {
        var c = VoiceGate.Context()
        c.secondsSinceSpeechEnded = 0.3
        c.spokenRecently = "Here are the top results for your search, sir."
        XCTAssertEqual(VoiceGate.utterance("search sir", confidence: 0.9, context: c), .drop("echo"))
        XCTAssertEqual(VoiceGate.utterance("results", confidence: 0.9, context: c), .drop("echo"))
        XCTAssertEqual(VoiceGate.utterance("okay", confidence: 0.9, context: c), .drop("speech tail"))
        XCTAssertEqual(VoiceGate.utterance("open the camera", confidence: 0.9, context: c), .accept)
        // After the user cut Jarvis off, even a short reply is the user's.
        c.userInterrupted = true
        XCTAssertEqual(VoiceGate.utterance("okay", confidence: 0.9, context: c), .accept)
        XCTAssertTrue(VoiceGate.unlikeSpeech("make a blue sphere", spoken: "Done, sir. I have created a red cube."))
        XCTAssertFalse(VoiceGate.unlikeSpeech("created a red cube", spoken: "Done, sir. I have created a red cube."))
    }

    func testTypingAndNoise() {
        var c = VoiceGate.Context()
        c.typing = true
        XCTAssertEqual(VoiceGate.utterance("click clack", confidence: 0.4, context: c), .drop("typing"))
        XCTAssertEqual(VoiceGate.utterance("Jarvis open YouTube", confidence: 0.9, context: c), .accept)
        XCTAssertEqual(VoiceGate.utterance("stop", confidence: 0.9, context: c), .accept)
        c.typing = false
        XCTAssertEqual(VoiceGate.utterance("um", confidence: 0.9, context: c), .drop("filler"))
        XCTAssertEqual(VoiceGate.utterance("음", confidence: 0.9, context: c), .drop("filler"))
        XCTAssertEqual(VoiceGate.utterance("banana", confidence: 0.1, context: c), .drop("unclear"))
        c.lastUtterance = "open settings"
        c.secondsSinceLastUtterance = 1
        XCTAssertEqual(VoiceGate.utterance("Open settings.", confidence: 0.9, context: c), .drop("duplicate"))
    }

    func testPushToTalkAcceptsEverythingButEcho() {
        var c = VoiceGate.Context()
        c.pushToTalk = true
        c.typing = true
        XCTAssertEqual(VoiceGate.utterance("make a cube", confidence: 0.2, context: c), .accept)
        c.jarvisSpeaking = true
        c.spokenRecently = "make a cube"
        XCTAssertEqual(VoiceGate.utterance("make a cube", confidence: 0.9, context: c), .drop("echo"))
    }

    func testBargeIn() {
        var c = VoiceGate.Context()
        c.jarvisSpeaking = true
        c.spokenRecently = "Here are the top results for your search, sir."
        XCTAssertFalse(VoiceGate.bargeIn(partial: "here are the top", context: c))
        XCTAssertTrue(VoiceGate.bargeIn(partial: "stop", context: c))
        XCTAssertTrue(VoiceGate.bargeIn(partial: "자비스 잠깐", context: c))
        XCTAssertTrue(VoiceGate.bargeIn(partial: "open the camera app now please", context: c))
        XCTAssertFalse(VoiceGate.bargeIn(partial: "hmm", context: c))
        c.jarvisSpeaking = false
        XCTAssertFalse(VoiceGate.bargeIn(partial: "stop", context: c))
        XCTAssertTrue(VoiceGate.isStopCommand("stop"))
        XCTAssertTrue(VoiceGate.isStopCommand("그만해"))
        XCTAssertFalse(VoiceGate.isStopCommand("stop the music and open youtube and play a song"))
    }

    func testNamePrefixedCommands() {
        let m = WakeWordMatcher()
        XCTAssertEqual(m.matchNamePrefix("Jarvis, open YouTube")?.trailingCommand, "open YouTube")
        XCTAssertEqual(m.matchNamePrefix("hey jarvis play some music")?.trailingCommand, "play some music")
        XCTAssertEqual(m.matchNamePrefix("자비스 음악 틀어줘")?.trailingCommand, "음악 틀어줘")
        XCTAssertEqual(m.matchNamePrefix("자비스야, 3D 공간 열어")?.trailingCommand, "3D 공간 열어")
        XCTAssertNil(m.matchNamePrefix("Jarvis"))
        XCTAssertNil(m.matchNamePrefix("open youtube"))
        XCTAssertNil(m.matchNamePrefix("I told Jarvis about it"))
    }
}
