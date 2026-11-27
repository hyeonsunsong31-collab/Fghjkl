import UIKit

/// Launch installed apps by name (Korean or English) through their URL schemes.
/// iOS does not allow listing installed apps; this catalog covers popular apps
/// in Korea and worldwide plus Apple's own apps. Unknown apps fall back to an
/// App Store search, and anything else can be routed through the Jarvis Bridge shortcut.
enum AppCatalog {
    struct Entry {
        let names: [String]
        let url: String
        /// Website used when iOS will not open the app itself (shown in Jarvis' browser).
        var web: String? = nil
        var display: String { names.first ?? url }
    }

    static let entries: [Entry] = [
        // Apple
        Entry(names: ["settings", "설정"], url: UIApplication.openSettingsURLString),
        Entry(names: ["music", "apple music", "음악 앱", "뮤직"], url: "music://"),
        Entry(names: ["maps", "apple maps", "지도"], url: "maps://"),
        Entry(names: ["messages", "imessage", "메시지 앱", "문자 앱"], url: "sms:"),
        Entry(names: ["phone", "전화 앱"], url: "tel:"),
        Entry(names: ["mail", "메일"], url: "message://"),
        Entry(names: ["calendar", "캘린더", "달력"], url: "calshow://"),
        Entry(names: ["photos", "사진", "갤러리"], url: "photos-redirect://"),
        Entry(names: ["notes", "메모"], url: "mobilenotes://"),
        Entry(names: ["reminders", "미리 알림", "미리알림"], url: "x-apple-reminderkit://"),
        Entry(names: ["safari", "사파리"], url: "x-web-search://"),
        Entry(names: ["app store", "앱스토어", "앱 스토어"], url: "itms-apps://"),
        Entry(names: ["files", "파일"], url: "shareddocuments://"),
        Entry(names: ["shortcuts", "단축어"], url: "shortcuts://"),
        Entry(names: ["facetime", "페이스타임"], url: "facetime://"),
        Entry(names: ["weather", "날씨"], url: "weather://"),
        Entry(names: ["clock", "alarm clock", "시계"], url: "clock-alarm://"),
        Entry(names: ["podcasts", "팟캐스트"], url: "podcasts://"),
        Entry(names: ["books", "도서"], url: "ibooks://"),
        Entry(names: ["health", "건강"], url: "x-apple-health://"),
        Entry(names: ["wallet", "지갑", "월렛"], url: "shoebox://"),
        Entry(names: ["home", "홈 앱"], url: "com.apple.home://"),
        Entry(names: ["freeform", "프리폼"], url: "freeform://"),
        Entry(names: ["tv", "apple tv", "티비"], url: "videos://"),
        Entry(names: ["find my", "나의 찾기"], url: "findmy://"),
        Entry(names: ["swift playgrounds", "playgrounds", "플레이그라운드"], url: "swiftplaygrounds://"),
        // Korea
        Entry(names: ["kakaotalk", "kakao talk", "카카오톡", "카톡"], url: "kakaotalk://"),
        Entry(names: ["naver", "네이버"], url: "naversearchapp://", web: "https://m.naver.com"),
        Entry(names: ["naver map", "네이버 지도", "네이버지도"], url: "nmap://", web: "https://m.map.naver.com"),
        Entry(names: ["kakao map", "카카오맵", "카카오 맵"], url: "kakaomap://", web: "https://m.map.kakao.com"),
        Entry(names: ["tmap", "티맵"], url: "tmap://"),
        Entry(names: ["kakao t", "카카오 t", "카카오택시", "카카오 택시"], url: "kakaot://"),
        Entry(names: ["coupang", "쿠팡"], url: "coupang://", web: "https://m.coupang.com"),
        Entry(names: ["toss", "토스"], url: "supertoss://"),
        Entry(names: ["baemin", "배민", "배달의민족", "배달의 민족"], url: "baemin://"),
        Entry(names: ["melon", "멜론"], url: "melonapp://", web: "https://m.melon.com"),
        Entry(names: ["genie", "지니"], url: "genieplayer://", web: "https://mw.genie.co.kr"),
        Entry(names: ["naver webtoon", "네이버 웹툰", "웹툰"], url: "naverwebtoon://", web: "https://m.comic.naver.com"),
        Entry(names: ["naver cafe", "네이버 카페"], url: "navercafe://", web: "https://m.cafe.naver.com"),
        // Global
        Entry(names: ["youtube", "유튜브"], url: "youtube://", web: "https://m.youtube.com"),
        Entry(names: ["youtube music", "유튜브 뮤직"], url: "youtubemusic://", web: "https://music.youtube.com"),
        Entry(names: ["spotify", "스포티파이"], url: "spotify://", web: "https://open.spotify.com"),
        Entry(names: ["instagram", "인스타그램", "인스타"], url: "instagram://", web: "https://www.instagram.com"),
        Entry(names: ["x", "twitter", "트위터", "엑스"], url: "twitter://", web: "https://x.com"),
        Entry(names: ["facebook", "페이스북"], url: "fb://", web: "https://m.facebook.com"),
        Entry(names: ["whatsapp", "왓츠앱"], url: "whatsapp://", web: "https://web.whatsapp.com"),
        Entry(names: ["line", "라인"], url: "line://"),
        Entry(names: ["telegram", "텔레그램"], url: "tg://", web: "https://web.telegram.org"),
        Entry(names: ["chrome", "google chrome", "크롬"], url: "googlechrome://"),
        Entry(names: ["google maps", "구글 지도", "구글맵"], url: "comgooglemaps://", web: "https://maps.google.com"),
        Entry(names: ["gmail", "지메일"], url: "googlegmail://", web: "https://mail.google.com"),
        Entry(names: ["google drive", "구글 드라이브"], url: "googledrive://", web: "https://drive.google.com"),
        Entry(names: ["netflix", "넷플릭스"], url: "nflx://", web: "https://www.netflix.com"),
        Entry(names: ["discord", "디스코드"], url: "discord://", web: "https://discord.com/app"),
        Entry(names: ["slack", "슬랙"], url: "slack://", web: "https://app.slack.com"),
        Entry(names: ["notion", "노션"], url: "notion://", web: "https://www.notion.so"),
        Entry(names: ["zoom", "줌"], url: "zoomus://", web: "https://zoom.us"),
        Entry(names: ["reddit", "레딧"], url: "reddit://", web: "https://www.reddit.com"),
        Entry(names: ["tiktok", "틱톡"], url: "snssdk1233://", web: "https://www.tiktok.com"),
    ]

    /// Best catalog match for a spoken/typed app name.
    static func find(_ name: String) -> Entry? {
        let q = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        if let exact = entries.first(where: { $0.names.contains(q) }) { return exact }
        let compact = q.replacingOccurrences(of: " ", with: "")
        if let c = entries.first(where: { $0.names.contains { $0.replacingOccurrences(of: " ", with: "") == compact } }) { return c }
        var best: (Entry, Double)?
        for e in entries {
            for n in e.names {
                let s = FuzzyMatch.similarity(n, q)
                if s > (best?.1 ?? 0) { best = (e, s) }
            }
        }
        if let b = best, b.1 >= 0.75 { return b.0 }
        return nil
    }

    enum OpenResult {
        case opened(String)
        /// The app could not be opened, but it has a website to show instead.
        case web(String, URL)
        case failed(String)
    }

    /// Open an app by name.
    @MainActor
    static func open(_ name: String, korean ko: Bool) async -> OpenResult {
        if let entry = find(name), let url = URL(string: entry.url) {
            if await URLOpener.open(url) { return .opened(entry.display) }
            if let web = entry.web, let site = URL(string: web) { return .web(entry.display, site) }
            if !UIApplication.shared.canOpenURL(url) {
                return .failed(ko ? "\(entry.display) 앱이 설치되어 있지 않거나 iOS가 확인을 허용하지 않았습니다."
                                  : "\(entry.display) doesn't seem to be installed, or iOS wouldn't let me check.")
            }
            return .failed(ko ? "iOS가 Swift Playground 안에서 \(entry.display) 앱을 여는 것을 허용하지 않았습니다. TestFlight로 설치한 Jarvis에서는 바로 열립니다."
                              : "iOS didn't let me open \(entry.display) from inside Swift Playground; it opens directly when Jarvis is installed through TestFlight.")
        }
        let term = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        if let store = URL(string: "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term=\(term)"),
           await URLOpener.open(store) {
            return .failed(ko ? "\u{201C}\(name)\u{201D} 앱을 바로 여는 방법을 몰라 App Store에서 검색했습니다."
                              : "I don't know how to open \u{201C}\(name)\u{201D} directly, so I searched the App Store.")
        }
        return .failed(ko ? "\u{201C}\(name)\u{201D} 앱을 찾지 못했습니다." : "I couldn't find an app called \u{201C}\(name)\u{201D}.")
    }
}
