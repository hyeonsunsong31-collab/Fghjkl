import XCTest
@testable import JarvisCore

final class AgentCoreTests: XCTestCase {
    func testWorkflowLifecycleAndNarration() throws {
        var wf = Workflow(title: "Build scene", originalRequest: "make a cube and clone it", language: .english,
                          steps: [WorkflowStep(title: "Create cube"), WorkflowStep(title: "Clone cube")])
        wf.start(step: 0)
        wf.succeed(step: 0, summary: "cube#1")
        XCTAssertEqual(wf.nextPendingIndex, 1)
        wf.start(step: 1)
        wf.markInterrupted()           // simulated crash during step 2
        XCTAssertEqual(wf.status, .interrupted)
        XCTAssertEqual(wf.nextPendingIndex, 1)
        let data = try JSONEncoder().encode(WorkflowCheckpoint(workflow: wf, savedAt: Date()))
        var restored = try JSONDecoder().decode(WorkflowCheckpoint.self, from: data).workflow
        restored.start(step: 1)
        restored.succeed(step: 1, summary: "cube#2")
        XCTAssertEqual(restored.status, .succeeded)
        XCTAssertEqual(restored.progress, 1)
        XCTAssertTrue(restored.narration(.korean).contains("✓ 2. Clone cube"))
    }

    func testTimeEstimator() {
        var t = TimeEstimator()
        XCTAssertEqual(t.estimate(key: "deepThink", cerebellar: nil), 12)
        for _ in 0..<20 { t.record(key: "webSearch", seconds: 8) }
        XCTAssertEqual(t.estimate(key: "webSearch", cerebellar: 6), 7, accuracy: 0.1)
        XCTAssertEqual(TimeEstimator.phrase(8, language: .korean), "약 8초 정도 걸릴 예정입니다.")
        XCTAssertEqual(TimeEstimator.phrase(1, language: .english), "This should take approximately 1 second, sir.")
    }

    func testPersonaConfirmationsAreFormalAndControlled() {
        let oc = OutputController()
        let grammar = CommandGrammar()
        let samples = ["make three red cubes", "파란 구 두 개 만들어줘", "open the 3D space", "3D 공간 열어줘",
                       "play bohemian rhapsody", "아이유 노래 틀어줘", "clone it twice", "set a timer for 5 minutes",
                       "turn on the flashlight", "엄마한테 전화해줘", "export the model", "배경화면으로 저장해줘"]
        for s in samples {
            let r = grammar.parse(s)
            guard let cmd = r.commands.first else { XCTFail("no parse: \(s)"); continue }
            let reply = Persona.confirmation(for: cmd, language: r.language)
            XCTAssertFalse(reply.isEmpty, s)
            let v = oc.verify(reply, expected: r.language, toolsSucceeded: true, characterLimit: 400, forSpeech: true)
            XCTAssertTrue(v.isEmpty, "\(s) → \(reply) violates \(v)")
        }
        XCTAssertEqual(Persona.confirmation(for: grammar.parse("make three red cubes").commands[0], language: .english), "Three red cubes, as requested, sir.")
        XCTAssertTrue(Persona.confirmation(for: grammar.parse("파란 구 두 개 만들어줘").commands[0], language: .korean).contains("파란색 구 2개"))
        XCTAssertTrue(Persona.acknowledgeSuggestion("increase the radius to 0.4 metres", language: .english).hasPrefix("An excellent suggestion, sir."))
    }

    func testOptionsAreExecutableUtterances() {
        let grammar = CommandGrammar()
        let gen = OptionGenerator()
        for lang in DetectedLanguage.allCases {
            let cmd = Command(intent: .createObject, parameters: ["shape": "cube"], confidence: 1, text: "")
            let (opts, recs) = gen.options(after: cmd, language: lang, success: true)
            XCTAssertEqual(opts.count, 3)
            XCTAssertFalse(recs.isEmpty)
            for o in opts {
                XCTAssertFalse(grammar.parse(o.utterance).isEmpty, "option '\(o.utterance)' must be executable")
            }
        }
    }

    func testHandGesturePinchDragAndTwoHandScale() {
        var g = HandGestureInterpreter(mirrored: false)
        func hand(x: Double, pinch: Bool) -> HandLandmarks {
            HandLandmarks(thumbTip: Point2(x: x, y: 0.5), indexTip: Point2(x: x + (pinch ? 0.01 : 0.15), y: 0.5),
                          wrist: Point2(x: x, y: 0.8), middleMCP: Point2(x: x, y: 0.6), confidence: 0.9, chirality: nil)
        }
        var t = 0.0
        func step(_ hands: [HandLandmarks]) -> [HandGestureEvent] { t += 1.0 / 30; return g.process(hands, time: t) }
        XCTAssertTrue(step([hand(x: 0.3, pinch: false)]).contains { if case .pointer = $0 { return true } else { return false } })
        XCTAssertTrue(step([hand(x: 0.3, pinch: true)]).contains { if case .grabBegan = $0 { return true } else { return false } })
        XCTAssertTrue(step([hand(x: 0.35, pinch: true)]).contains { if case .grabMoved = $0 { return true } else { return false } })
        XCTAssertTrue(step([hand(x: 0.35, pinch: false)]).contains { if case .grabEnded = $0 { return true } else { return false } })
        _ = step([hand(x: 0.4, pinch: true), hand(x: 0.6, pinch: true)])
        var lastScale = 0.0
        for k in 1...10 {
            for e in step([hand(x: 0.4 - Double(k) * 0.01, pinch: true), hand(x: 0.6 + Double(k) * 0.01, pinch: true)]) {
                if case .twoHandScale(let s) = e { lastScale = s }
            }
        }
        XCTAssertGreaterThan(lastScale, 1.5, "spreading hands must scale up")
    }

    func testOneEuroFilterSmoothsJitter() {
        var f = OneEuroFilter()
        var rng = SplitMix64(seed: 3)
        var out: [Double] = []
        for i in 0..<200 { out.append(f.filter(0.5 + Double(rng.nextUnit() - 0.5) * 0.02, time: Double(i) / 60)) }
        let tail = out.suffix(100)
        let mean = tail.reduce(0, +) / Double(tail.count)
        let variance = tail.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(tail.count)
        XCTAssertLessThan(variance.squareRoot(), 0.004)
    }
}
