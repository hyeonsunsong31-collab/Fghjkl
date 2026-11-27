import XCTest
@testable import JarvisCore

final class MusicAndConfirmationTests: XCTestCase {
    private func query(_ text: String) -> String? {
        let r = CommandGrammar().parse(text)
        guard let c = r.commands.first, c.intent == .playMusic else { return "NOT-MUSIC" }
        return c.parameters["query"]
    }

    func testMusicQueriesKeepTheRequestedSong() {
        XCTAssertEqual(query("아이유 노래 틀어줘"), "아이유")
        XCTAssertEqual(query("아이유 좋은날 재생해줘"), "아이유 좋은날")
        XCTAssertEqual(query("BTS 다이너마이트 들려줘"), "BTS 다이너마이트")
        XCTAssertEqual(query("유튜브에서 아이유 밤편지 틀어줘"), "아이유 밤편지")
        XCTAssertEqual(query("자비스, 아이유 밤편지 틀어 줄래?"), "아이유 밤편지")
        XCTAssertEqual(query("Dynamite 틀어줘"), "Dynamite")
        XCTAssertEqual(query("put on Shape of You"), "Shape of You")
        XCTAssertEqual(query("play Blinding Lights by The Weeknd"), "Blinding Lights by The Weeknd")
        XCTAssertEqual(query("play the song Yesterday by the Beatles"), "Yesterday by the Beatles")
        XCTAssertEqual(query("can you play Hotel California please"), "Hotel California")
        XCTAssertEqual(query("Jarvis, play Let It Be"), "Let It Be")
        XCTAssertNil(query("음악 틀어줘"))
        XCTAssertNil(query("play some music"))
    }

    func testAppLaunchVerbs() {
        let g = CommandGrammar()
        XCTAssertEqual(g.parse("멜론 켜줘").commands.first?.parameters["app"], "멜론")
        XCTAssertEqual(g.parse("launch spotify").commands.first?.parameters["app"], "spotify")
        XCTAssertEqual(g.parse("블루투스 켜줘").commands.first?.intent, .systemSetting, "settings still win over app launch")
        XCTAssertEqual(g.parse("손전등 켜").commands.first?.intent, .flashlightOn)
    }

    func testConfirmationReplies() {
        for yes in ["yes", "Yes.", "yes please", "네", "네.", "네 걸어줘", "응", "그래", "좋아", "okay go ahead"] {
            XCTAssertEqual(ConfirmationReply.classify(yes), true, yes)
        }
        for no in ["no", "아니요", "아니", "취소해", "don't call", "do not send it", "하지 마"] {
            XCTAssertEqual(ConfirmationReply.classify(no), false, no)
        }
        for other in ["네이버 열어줘", "now open youtube", "I know"] {
            XCTAssertNil(ConfirmationReply.classify(other), other)
        }
    }

    func testYouTubeResultsParsingAndMatching() {
        let html = """
        <script>var ytInitialData = {"contents":{"twoColumnSearchResultsRenderer":{"primaryContents":{"sectionListRenderer":{"contents":[{"itemSectionRenderer":{"contents":[
        {"adSlotRenderer":{"x":1}},
        {"videoRenderer":{"videoId":"AAAAAAAAAA1","thumbnail":{},"title":{"runs":[{"text":"Lofi beats \\u0026 chill"}]}}},
        {"videoRenderer":{"videoId":"fJ9rUzIMcZQ","thumbnail":{},"title":{"runs":[{"text":"Queen – Bohemian Rhapsody (Official Video Remastered)"}]}}},
        {"videoRenderer":{"videoId":"fJ9rUzIMcZQ","title":{"runs":[{"text":"duplicate"}]}}}
        ]}}]}}}}};</script>
        """
        let videos = YouTubeResults.parse(html)
        XCTAssertEqual(videos.map(\.id), ["AAAAAAAAAA1", "fJ9rUzIMcZQ"])
        XCTAssertEqual(videos.first?.title, "Lofi beats & chill")
        XCTAssertEqual(YouTubeResults.bestMatch(videos, for: "Bohemian Rhapsody by Queen")?.id, "fJ9rUzIMcZQ",
                       "the result whose title matches the request wins over an unrelated first result")
        XCTAssertEqual(YouTubeResults.bestMatch(videos, for: "아이유")?.id, "AAAAAAAAAA1", "no match: first result")
        XCTAssertTrue(YouTubeResults.parse("<html>no data</html>").isEmpty)
    }

    func testKnownAppsAreConfidentCommands() {
        let grammar = CommandGrammar()
        XCTAssertEqual(grammar.parse("open youtube").commands.first?.intent, .openApp)
        CommandGrammar.isKnownApp = { ["youtube", "유튜브", "멜론"].contains($0.lowercased()) }
        defer { CommandGrammar.isKnownApp = nil }
        XCTAssertGreaterThanOrEqual(grammar.parse("open youtube").confidence, 0.9)
        XCTAssertGreaterThanOrEqual(grammar.parse("유튜브 열어줘").confidence, 0.9)
        XCTAssertGreaterThanOrEqual(grammar.parse("멜론 켜줘").confidence, 0.9)
        XCTAssertLessThan(grammar.parse("open zzqx").confidence, 0.88)
    }
}
