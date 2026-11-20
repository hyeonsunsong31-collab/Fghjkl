import XCTest
@testable import JarvisCore

final class GrammarTests: XCTestCase {
    let g = CommandGrammar()

    func intent(_ s: String, file: StaticString = #filePath, line: UInt = #line) -> CommandIntent? {
        g.parse(s).commands.first?.intent
    }

    func assertIntent(_ s: String, _ expected: CommandIntent, file: StaticString = #filePath, line: UInt = #line) {
        let r = g.parse(s)
        XCTAssertEqual(r.commands.first?.intent, expected, "\"\(s)\" → \(r.commands.map { "\($0.intent) \($0.parameters) \($0.confidence)" })", file: file, line: line)
    }

    func testAssistantControlEnglish() {
        assertIntent("wake up Jarvis", .wake)
        assertIntent("Jarvis, go to sleep", .sleep)
        assertIntent("stop talking", .stopSpeaking)
        assertIntent("mute my microphone", .muteMic)
        assertIntent("unmute the mic", .unmuteMic)
        assertIntent("mute your voice", .muteVoice)
        assertIntent("text only please", .muteVoice)
        assertIntent("what can you do", .help)
        assertIntent("show me the history", .showHistory)
        assertIntent("show the neural core", .showBrain)
        assertIntent("open settings", .openSettings)
        assertIntent("turn on deep think mode", .deepThinkOn)
        assertIntent("deep think off", .deepThinkOff)
        assertIntent("use the lewis voice", .setVoice)
        assertIntent("speak faster", .speakFaster)
        assertIntent("please slow down", .speakSlower)
        assertIntent("resume the task", .resumeTask)
    }

    func testAssistantControlKorean() {
        assertIntent("자비스 잘 자", .sleep)
        assertIntent("그만", .stopSpeaking)
        assertIntent("마이크 꺼줘", .muteMic)
        assertIntent("마이크 켜줘", .unmuteMic)
        assertIntent("음성 꺼", .muteVoice)
        assertIntent("목소리 다시 켜줘", .unmuteVoice)
        assertIntent("뭘 할 수 있어?", .help)
        assertIntent("대화 기록 보여줘", .showHistory)
        assertIntent("신경망 보여줘", .showBrain)
        assertIntent("심층 사고 모드 켜줘", .deepThinkOn)
        assertIntent("심층사고 꺼", .deepThinkOff)
        assertIntent("천천히 말해줘", .speakSlower)
        assertIntent("하던 작업 계속해", .resumeTask)
    }

    func test3DSpace() {
        assertIntent("open the 3D project space", .open3D)
        assertIntent("close the workspace", .close3D)
        assertIntent("3D 공간 열어줘", .open3D)
        assertIntent("3D 프로젝트 닫아", .close3D)
        assertIntent("turn off hand tracking", .handTrackingOff)
        assertIntent("enable hand gestures", .handTrackingOn)
        assertIntent("손 인식 꺼줘", .handTrackingOff)
        assertIntent("제스처 켜", .handTrackingOn)

        let create = g.parse("make three red cubes").commands.first
        XCTAssertEqual(create?.intent, .createObject)
        XCTAssertEqual(create?["shape"], "cube")
        XCTAssertEqual(create?["color"], "red")
        XCTAssertEqual(create?["count"], "3")

        let ko = g.parse("파란 구 두 개 만들어줘").commands.first
        XCTAssertEqual(ko?.intent, .createObject)
        XCTAssertEqual(ko?["shape"], "sphere")
        XCTAssertEqual(ko?["color"], "blue")
        XCTAssertEqual(ko?["count"], "2")

        XCTAssertEqual(g.parse("큰 도넛 하나 추가해").commands.first?["shape"], "torus")
        assertIntent("build me an iron helmet", .generateModel)
        assertIntent("로봇 팔 만들어줘", .generateModel)

        let clone = g.parse("clone it twice").commands.first
        XCTAssertEqual(clone?.intent, .cloneObject)
        XCTAssertEqual(clone?["count"], "2")
        XCTAssertEqual(g.parse("이거 세 번 복제해").commands.first?["count"], "3")
        assertIntent("delete the blue sphere", .deleteObject)
        assertIntent("빨간 큐브 지워", .deleteObject)
        assertIntent("delete everything", .clearScene)

        let move = g.parse("move it left 30 cm").commands.first
        XCTAssertEqual(move?.intent, .moveObject)
        XCTAssertEqual(move?["direction"], "left")
        XCTAssertEqual(Double(move?["amount"] ?? "0") ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertEqual(g.parse("오른쪽으로 옮겨").commands.first?["direction"], "right")

        let scale = g.parse("make the red cube twice as big").commands.first
        XCTAssertEqual(scale?.intent, .scaleObject)
        XCTAssertEqual(scale?["factor"], "2.0")
        XCTAssertEqual(scale?["targetColor"], "red")
        assertIntent("작게 만들어", .scaleObject)
        XCTAssertEqual(g.parse("rotate it 90 degrees").commands.first?["degrees"], "90.0")
        assertIntent("파란색으로 바꿔줘", .colorObject)
        assertIntent("paint the sphere gold", .colorObject)
        assertIntent("undo", .undo)
        assertIntent("되돌려", .undo)
        assertIntent("export the model", .exportModel)
        assertIntent("set this as my wallpaper", .saveWallpaper)
        assertIntent("배경화면으로 저장해줘", .saveWallpaper)
        assertIntent("reset the view", .resetCamera)
    }

    func testCompoundCommands() {
        let r = g.parse("open the 3D space and make a red cube then clone it twice")
        XCTAssertEqual(r.commands.map(\.intent), [.open3D, .createObject, .cloneObject])
        let ko = g.parse("3D 공간 열고 큐브 만들어줘")
        XCTAssertEqual(ko.commands.map(\.intent), [.open3D, .createObject])
        let colorPhrase = g.parse("make a black and white cube")
        XCTAssertEqual(colorPhrase.commands.count, 1)
        XCTAssertEqual(colorPhrase.commands.first?.intent, .createObject)
    }

    func testMusicAndWeb() {
        let m = g.parse("play Bohemian Rhapsody by Queen").commands.first
        XCTAssertEqual(m?.intent, .playMusic)
        XCTAssertEqual(m?["query"], "bohemian rhapsody by queen")
        let ko = g.parse("아이유 노래 틀어줘").commands.first
        XCTAssertEqual(ko?.intent, .playMusic)
        XCTAssertEqual(ko?["query"], "아이유")
        assertIntent("play some music", .playMusic)
        assertIntent("pause", .pauseMusic)
        assertIntent("stop the music", .stopMusic)
        assertIntent("음악 꺼줘", .stopMusic)
        assertIntent("next song", .nextTrack)
        assertIntent("다음 곡", .nextTrack)
        assertIntent("open the browser", .openBrowser)
        let s = g.parse("search for the best ramen in Seoul").commands.first
        XCTAssertEqual(s?.intent, .webSearch)
        XCTAssertEqual(s?["query"], "best ramen seoul")
        XCTAssertEqual(g.parse("서울 날씨 검색해줘").commands.first?["query"], "서울 날씨")
        XCTAssertEqual(g.parse("go to apple.com").commands.first?["url"], "https://apple.com")
    }

    func testDevice() {
        assertIntent("open KakaoTalk", .openApp)
        XCTAssertEqual(g.parse("카카오톡 열어줘").commands.first?["app"], "카카오톡")
        XCTAssertEqual(g.parse("launch spotify").commands.first?["app"], "spotify")
        assertIntent("turn on the flashlight", .flashlightOn)
        assertIntent("손전등 꺼", .flashlightOff)
        XCTAssertEqual(g.parse("set brightness to 50%").commands.first?["level"], "0.5")
        XCTAssertEqual(g.parse("밝기 올려줘").commands.first?["delta"], "0.2")
        assertIntent("turn the volume down", .setVolume)
        assertIntent("how much battery is left", .batteryStatus)
        assertIntent("what time is it", .timeQuery)
        assertIntent("지금 몇 시야", .timeQuery)
        assertIntent("오늘 며칠이야", .dateQuery)
        XCTAssertEqual(g.parse("set a timer for 5 minutes").commands.first?["seconds"], "300")
        XCTAssertEqual(g.parse("3분 타이머 맞춰줘").commands.first?["seconds"], "180")
        let alarm = g.parse("오전 7시 30분에 알람 맞춰줘").commands.first
        XCTAssertEqual(alarm?["hour"], "7")
        XCTAssertEqual(alarm?["minute"], "30")
        XCTAssertEqual(g.parse("set an alarm for 6:45 pm").commands.first?["hour"], "18")
        let wifi = g.parse("turn off wifi").commands.first
        XCTAssertEqual(wifi?.intent, .systemSetting)
        XCTAssertEqual(wifi?["setting"], "wifi")
        XCTAssertEqual(wifi?["value"], "off")
        XCTAssertEqual(g.parse("블루투스 켜줘").commands.first?["setting"], "bluetooth")
        XCTAssertEqual(g.parse("call mum").commands.first?["contact"], "mum")
        XCTAssertEqual(g.parse("엄마한테 전화해줘").commands.first?["contact"], "엄마")
        let msg = g.parse("send a text to Minji saying I'm running late").commands.first
        XCTAssertEqual(msg?.intent, .message)
        XCTAssertEqual(msg?["contact"], "Minji")
        XCTAssertEqual(msg?["body"], "I'm running late")
        XCTAssertEqual(g.parse("run the shortcut \"Morning Routine\"").commands.first?["name"], "Morning Routine")
    }

    func testFreeFormDoesNotMatch() {
        XCTAssertTrue(g.parse("Tell me a story about a dragon who loved tea").isEmpty || g.parse("Tell me a story about a dragon who loved tea").confidence < 0.6)
        XCTAssertTrue(g.parse("Why do cats purr?").isEmpty)
        XCTAssertTrue(g.parse("오늘 기분이 좀 우울해").isEmpty)
    }
}

final class LanguageTests: XCTestCase {
    func testDetection() {
        XCTAssertEqual(LanguageDetector.detect("Open the 3D space").language, .english)
        XCTAssertEqual(LanguageDetector.detect("3D 공간 열어줘").language, .korean)
        XCTAssertEqual(LanguageDetector.detect("ok", previous: .korean).language, .korean)
    }

    func testWakeWord() {
        let m = WakeWordMatcher()
        XCTAssertNotNil(m.match("wake up Jarvis"))
        XCTAssertNotNil(m.match("Wake up, Jervis."))
        XCTAssertNotNil(m.match("wakeup javis"))
        XCTAssertNotNil(m.match("okay Jarvis wake up"))
        XCTAssertEqual(m.match("wake up jarvis open the 3D space")?.trailingCommand, "open the 3D space")
        XCTAssertNotNil(m.match("웨이크 업 자비스"))
        XCTAssertNotNil(m.match("자비스 일어나"))
        XCTAssertEqual(m.match("자비스 일어나 3D 공간 열어")?.language, .korean)
        XCTAssertTrue(m.match("자비스 일어나 3D 공간 열어")?.trailingCommand.contains("3D공간열어") ?? false)
        XCTAssertNil(m.match("I woke up early today"))
        XCTAssertNil(m.match("the service was great"))
        XCTAssertNil(m.match("오늘 일찍 일어났어"))
    }

    func testNumbers() {
        XCTAssertEqual(NumberParsing.duration(in: "1 hour and 30 minutes"), 5400)
        XCTAssertEqual(NumberParsing.duration(in: "한 시간 반"), 3600)
        XCTAssertEqual(NumberParsing.duration(in: "1시간 30분"), 5400)
        XCTAssertEqual(NumberParsing.percentage(in: "밝기 오십 퍼센트"), 50)
        XCTAssertEqual(NumberParsing.clockTime(in: "7am")?.hour, 7)
        XCTAssertEqual(NumberParsing.clockTime(in: "오후 3시 반")?.hour, 15)
        XCTAssertEqual(NumberParsing.clockTime(in: "오후 3시 반")?.minute, 30)
        XCTAssertNil(NumberParsing.clockTime(in: "2시간 동안"))
    }

    func testHangul() {
        XCTAssertEqual(Hangul.decompose("한"), "ㅎㅏㄴ")
        XCTAssertEqual(Hangul.objectParticle(for: "큐브"), "를")
        XCTAssertEqual(Hangul.objectParticle(for: "원통"), "을")
        XCTAssertGreaterThan(FuzzyMatch.similarity("만들어줘", "만들어 줘"), 0.8)
    }
}
