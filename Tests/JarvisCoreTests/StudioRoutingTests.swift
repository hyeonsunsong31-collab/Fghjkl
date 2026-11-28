import XCTest
@testable import JarvisCore

final class StudioRoutingTests: XCTestCase {
    let g = CommandGrammar()

    func work(_ text: String) -> Bool { StudioRouting.isStudioWork(text, parsed: g.parse(text)) }

    /// With the studio open, edits of the product go to its queue…
    func testEditsGoToTheStudio() {
        for text in ["make the snake faster and add a timer", "add a timer", "make the background black", "3 lives",
                     "change the snake color to red", "remove the sound", "add enemies", "make the paddle bigger", "make it harder",
                     "뱀을 더 빠르게 하고 타이머 추가해줘", "배경을 검게 바꿔", "목숨 5개로 해줘"] {
            XCTAssertTrue(work(text), text)
        }
    }

    /// …while assistant commands keep their meaning.
    func testAssistantCommandsKeepTheirMeaning() {
        for text in ["set a timer for 5 minutes", "play some music", "what time is it", "open youtube", "go to sleep",
                     "음악 틀어줘", "몇 시야", "close the studio"] {
            XCTAssertFalse(work(text), text)
        }
    }

    /// Outside the studio, timers and 3D objects stay what they were.
    func testNoRegressionsOutsideTheStudio() {
        XCTAssertEqual(g.parse("make a 5 minute timer").commands.first?.intent == .buildProgram, false)
        XCTAssertEqual(g.parse("make a red cube").commands.first?.intent, .createObject)
        XCTAssertEqual(g.parse("make a breakout clone").commands.first?.intent, .buildProgram)
        XCTAssertEqual(g.parse("make a timer app").commands.first?.intent, .buildProgram)
    }
}
