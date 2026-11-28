import XCTest
@testable import JarvisCore

final class DesignGrammarTests: XCTestCase {
    private func intents(_ text: String) -> [CommandIntent] { CommandGrammar().parse(text).commands.map(\.intent) }

    func testDetailedDesignRequestsStayWhole() {
        let r = CommandGrammar().parse("make a red sports car with black wheels and a spoiler")
        XCTAssertEqual(r.commands.map(\.intent), [.generateModel])
        XCTAssertGreaterThanOrEqual(r.confidence, 0.9)
        let request = r.commands.first?.parameters["request"] ?? ""
        XCTAssertTrue(request.contains("spoiler") && request.contains("black wheels"), request)
        XCTAssertEqual(intents("design a two story house with a blue roof and add a chimney"), [.generateModel])
        XCTAssertEqual(intents("검은 바퀴가 6개인 빨간 스포츠카 만들어줘"), [.generateModel])
        XCTAssertEqual(intents("빨간 지붕이 있는 이층집 만들어 줘"), [.generateModel])
        XCTAssertEqual(intents("open the 3D space and make a castle"), [.open3D, .generateModel])
        XCTAssertEqual(intents("make a car with black wheels"), [.generateModel])
    }

    func testRefinementsOfTheCurrentDesign() {
        XCTAssertEqual(intents("make the wheels gold"), [.refineModel])
        XCTAssertEqual(intents("add a chimney"), [.refineModel])
        XCTAssertEqual(intents("remove the spoiler"), [.refineModel])
        XCTAssertEqual(intents("make the wheels bigger"), [.refineModel])
        XCTAssertEqual(intents("make the car's wheels black"), [.refineModel])
        XCTAssertEqual(intents("add two more towers"), [.refineModel])
        XCTAssertEqual(intents("바퀴를 금색으로 바꿔"), [.refineModel])
        XCTAssertEqual(intents("굴뚝 추가해"), [.refineModel])
        XCTAssertEqual(intents("스포일러 빼줘"), [.refineModel])
        XCTAssertEqual(intents("지붕을 파란색으로 칠해"), [.refineModel])
    }

    func testPlainCommandsAreUnchanged() {
        XCTAssertEqual(intents("make a red cube"), [.createObject])
        XCTAssertEqual(intents("make it bigger"), [.scaleObject])
        XCTAssertEqual(intents("paint it gold"), [.colorObject])
        XCTAssertEqual(intents("delete the red cube"), [.deleteObject])
        XCTAssertEqual(intents("clone it twice"), [.cloneObject])
        XCTAssertEqual(intents("make three red cubes"), [.createObject])
        XCTAssertEqual(intents("파란 구 만들어줘"), [.createObject])
    }

    func testRenderStyle() {
        XCTAssertEqual(CommandGrammar().parse("hologram mode").commands.first?.parameters["style"], "hologram")
        XCTAssertEqual(CommandGrammar().parse("실사 모드로 보여줘").commands.first?.parameters["style"], "solid")
    }
}
