import Foundation

/// Everything a request says about a program to build or change (English and Korean):
/// what it is, which template fits, language, features, colours per part, numbers,
/// website sections, title, style and what to leave out.
struct ProgramBrief: Codable, Equatable {
    var request: String
    var kind: String = "app"            // game, website, app, ai, script
    var template: String?
    var title: String?
    var subject: String?                // "bakery", "빵집", "space" …
    var language: String = "web"        // web (HTML/CSS/JS) unless another one is asked for
    var features: [String] = []
    var excluded: [String] = []
    var colors: [String: String] = [:]  // role → colour key
    var numbers: [String: Double] = [:] // speed, lives, levels, time, grid, players, items, win
    var sections: [String] = []
    var styles: [String] = []
    var korean = false

    func wants(_ f: String) -> Bool { features.contains(f) && !excluded.contains(f) }

    // MARK: Vocabulary

    static let templates: [(key: String, words: [String])] = [
        ("snake", ["snake game", "snake", "snakes", "뱀 게임", "뱀게임", "뱀", "스네이크", "지렁이"]),
        ("breakout", ["brick breaker", "breakout", "arkanoid", "bricks", "brick", "벽돌깨기", "벽돌 깨기", "벽돌", "블록 깨기"]),
        ("pong", ["ping pong", "table tennis", "air hockey", "pong", "paddle game", "탁구", "핑퐁", "에어하키", "퐁"]),
        ("hopper", ["flappy bird", "flappy", "flap", "hopper", "플래피버드", "플래피"]),
        ("shooter", ["space shooter", "shoot em up", "space invaders", "invaders", "shooter", "shmup", "galaga", "shooting", "슈팅 게임", "슈팅",
                     "비행기 게임", "우주 전쟁", "인베이더", "갤러그"]),
        ("platformer", ["platform game", "platformer", "side scroller", "jump and run", "mario", "플랫포머", "플랫폼 게임", "횡스크롤", "점프 게임", "마리오"]),
        ("blocks", ["falling blocks", "falling block", "block puzzle", "tetris", "tetromino", "테트리스", "블록 쌓기", "떨어지는 블록"]),
        ("memory", ["memory game", "card matching", "matching game", "match pairs", "concentration", "memory", "기억력 게임", "기억력", "카드 짝",
                    "짝 맞추기", "짝맞추기", "카드 뒤집기"]),
        ("tictactoe", ["tic tac toe", "tictactoe", "noughts and crosses", "five in a row", "connect five", "gomoku", "틱택토", "삼목", "오목"]),
        ("merge", ["2048", "number merge", "merge game", "merge numbers", "숫자 합치기", "숫자 퍼즐"]),
        ("runner", ["endless runner", "infinite runner", "dino game", "dinosaur game", "runner", "러너", "달리기 게임", "공룡 게임", "무한 달리기"]),
        ("maze", ["maze", "labyrinth", "미로"]),
        ("whack", ["whack a mole", "whack mole", "mole", "두더지 잡기", "두더지"]),
        ("clicker", ["cookie clicker", "idle game", "incremental", "clicker", "클리커", "방치형", "클릭 게임"]),
        ("quiz", ["quiz", "trivia", "퀴즈", "문제 맞추기", "상식 게임"]),
        ("dodge", ["dodge", "dodging", "avoid the", "피하기", "피하는 게임", "똥 피하기"]),
        ("todo", ["to do list", "todo list", "to do", "todo", "task list", "task manager", "checklist", "할 일", "할일", "투두", "체크리스트"]),
        ("notes", ["note taking", "notepad", "notes", "memo", "메모장", "메모", "노트"]),
        ("calculator", ["calculator", "계산기"]),
        ("timer", ["pomodoro", "stopwatch", "countdown", "timer", "뽀모도로", "스톱워치", "타이머"]),
        ("paint", ["drawing app", "paint", "drawing", "sketch", "whiteboard", "그림판", "그림 그리기", "페인트", "스케치"]),
        ("piano", ["piano", "synthesizer", "synth", "drum pad", "drums", "피아노", "건반", "드럼", "신디사이저"]),
        ("chatbot", ["chatbot", "chat bot", "chat assistant", "assistant bot", "talking bot", "챗봇", "채팅봇", "대화 봇", "대화형 ai", "상담 봇"]),
        ("neural", ["neural network", "neural net", "machine learning", "deep learning", "perceptron", "train a model", "신경망", "머신러닝",
                    "딥러닝", "퍼셉트론", "학습하는 ai"]),
        ("classifier", ["sentiment analysis", "sentiment", "text classifier", "classifier", "spam filter", "spam detector", "emotion detector",
                        "감정 분석", "감성 분석", "분류기", "스팸 필터"]),
        ("textgen", ["text generator", "markov", "poem generator", "story generator", "name generator", "문장 생성기", "글 생성", "시 생성",
                     "이름 생성기", "문장 생성"]),
        ("portfolio", ["portfolio", "포트폴리오"]),
        ("blog", ["blog", "블로그"]),
        ("store", ["online store", "e commerce", "ecommerce", "online shop", "shop", "store", "shopping", "쇼핑몰", "온라인 상점", "스토어"]),
        ("landing", ["landing page", "homepage", "home page", "website", "web site", "webpage", "web page", "site", "랜딩 페이지", "홈페이지",
                     "웹사이트", "웹 사이트", "사이트", "웹페이지"]),
    ]

    static let templateKind: [String: String] = [
        "snake": "game", "breakout": "game", "pong": "game", "hopper": "game", "shooter": "game", "platformer": "game", "blocks": "game",
        "memory": "game", "tictactoe": "game", "merge": "game", "runner": "game", "maze": "game", "whack": "game", "clicker": "game",
        "quiz": "game", "dodge": "game", "todo": "app", "notes": "app", "calculator": "app", "timer": "app", "paint": "app", "piano": "app",
        "chatbot": "ai", "neural": "ai", "classifier": "ai", "textgen": "ai", "portfolio": "website", "blog": "website", "store": "website",
        "landing": "website",
    ]

    static let kinds: [(key: String, words: [String])] = [
        ("game", ["video game", "game", "games", "arcade", "게임"]),
        ("website", ["website", "web site", "homepage", "home page", "landing page", "webpage", "web page", "site", "웹사이트", "홈페이지", "사이트", "웹페이지"]),
        ("ai", ["artificial intelligence", "ai", "bot", "인공지능", "에이아이", "봇"]),
        ("app", ["web app", "application", "app", "tool", "program", "utility", "dashboard", "앱", "어플", "애플리케이션", "프로그램", "도구", "대시보드"]),
        ("script", ["command line", "script", "cli", "스크립트"]),
    ]

    static let languages: [(key: String, words: [String])] = [
        ("python", ["python", "파이썬", "pygame"]), ("typescript", ["typescript", "타입스크립트"]),
        ("javascript", ["javascript", "node js", "nodejs", "node", "자바스크립트"]), ("cpp", ["c++", "cpp", "씨쁠쁠", "씨플플"]),
        ("csharp", ["c#", "csharp", "c sharp", "unity"]), ("java", ["java", "자바"]), ("kotlin", ["kotlin", "코틀린"]),
        ("swift", ["swift", "swiftui", "스위프트"]), ("rust", ["rust", "러스트"]), ("go", ["golang", "go language", "고 언어"]),
        ("lua", ["lua", "love2d", "루아"]), ("php", ["php"]), ("ruby", ["ruby", "루비"]), ("gdscript", ["godot", "gdscript", "고도 엔진"]),
        ("c", ["c language", "in c", "c 언어", "c언어"]), ("dart", ["dart", "flutter", "플러터"]), ("r", ["r language", "r 언어"]),
        ("bash", ["bash", "shell script", "배시"]), ("sql", ["sql", "database schema"]), ("react", ["react", "리액트"]), ("vue", ["vue", "뷰 js"]),
    ]

    static let featureWords: [(key: String, words: [String])] = [
        ("highscore", ["high score", "highscore", "best score", "leaderboard", "record", "최고 점수", "최고점수", "최고 기록", "순위", "랭킹", "리더보드"]),
        ("score", ["score", "scores", "points", "점수", "스코어"]),
        ("levels", ["levels", "level", "stages", "stage", "레벨", "단계", "스테이지"]),
        ("lives", ["lives", "life", "hearts", "목숨", "생명", "라이프", "하트"]),
        ("timer", ["time limit", "timed", "timer", "countdown", "제한 시간", "시간 제한", "타이머"]),
        ("sound", ["sound effects", "sound", "sounds", "sfx", "audio", "beeps", "효과음", "소리", "사운드"]),
        ("music", ["background music", "music", "bgm", "soundtrack", "배경 음악", "배경음악", "음악", "브금"]),
        ("pause", ["pause button", "pause", "일시정지", "일시 정지", "멈춤 버튼"]),
        ("touch", ["touch controls", "touch", "mobile", "phone", "tablet", "ipad", "iphone", "swipe", "터치", "모바일", "스와이프", "아이패드", "아이폰", "휴대폰", "핸드폰"]),
        ("darkmode", ["dark mode", "dark theme", "night mode", "다크 모드", "다크모드", "어두운 테마", "야간 모드"]),
        ("difficulty", ["difficulty", "difficulty levels", "easy mode", "hard mode", "난이도"]),
        ("powerups", ["power ups", "power up", "powerups", "powerup", "items", "bonuses", "아이템", "파워업", "보너스"]),
        ("enemies", ["enemies", "enemy", "monsters", "obstacles", "적들", "적", "몬스터", "장애물"]),
        ("boss", ["boss fight", "boss", "보스"]),
        ("twoplayer", ["two player", "two players", "2 player", "2 players", "multiplayer", "versus", "2인용", "2인", "두 명이", "두명이", "대전"]),
        ("ai", ["computer opponent", "ai opponent", "against the computer", "vs computer", "versus computer", "single player", "컴퓨터와", "컴퓨터 상대", "ai 상대", "인공지능 상대", "혼자서"]),
        ("save", ["save progress", "autosave", "save", "persist", "자동 저장", "저장"]),
        ("particles", ["particles", "particle", "explosions", "explosion", "effects", "파티클", "폭발 효과", "폭발", "이펙트"]),
        ("menu", ["start screen", "title screen", "main menu", "start menu", "시작 화면", "메인 메뉴", "타이틀 화면", "시작 메뉴"]),
        ("fullscreen", ["full screen", "fullscreen", "전체 화면", "전체화면"]),
        ("animation", ["animations", "animation", "animated", "smooth", "애니메이션", "부드러운"]),
        ("search", ["search", "filter", "검색", "필터"]),
        ("categories", ["categories", "tags", "folders", "카테고리", "태그", "폴더"]),
        ("export", ["export", "download", "내보내기", "다운로드"]),
        ("history", ["history", "기록 보기", "히스토리"]),
        ("cart", ["shopping cart", "cart", "basket", "checkout", "장바구니", "결제"]),
        ("responsive", ["responsive", "mobile friendly", "반응형"]),
    ]

    static let sectionWords: [(key: String, words: [String])] = [
        ("menu", ["food menu", "menu", "drinks", "메뉴판", "메뉴", "음료"]),
        ("about", ["about us", "about", "our story", "story", "소개", "회사 소개", "우리 이야기", "스토리"]),
        ("gallery", ["gallery", "photos", "pictures", "projects", "works", "갤러리", "사진", "작품", "프로젝트"]),
        ("contact", ["contact form", "contact", "get in touch", "연락처", "연락", "문의하기", "문의"]),
        ("pricing", ["pricing", "prices", "plans", "가격표", "가격", "요금제", "요금"]),
        ("testimonials", ["testimonials", "reviews", "후기", "리뷰"]),
        ("faq", ["faq", "questions", "자주 묻는 질문", "질문"]),
        ("team", ["our team", "team", "staff", "팀 소개", "팀", "직원"]),
        ("services", ["services", "features", "what we do", "서비스", "기능 소개"]),
        ("location", ["opening hours", "location", "map", "address", "hours", "directions", "오시는 길", "위치", "지도", "주소", "영업시간", "영업 시간"]),
        ("blog", ["blog", "news", "블로그", "소식", "뉴스"]),
        ("newsletter", ["newsletter", "subscribe", "뉴스레터", "구독"]),
        ("booking", ["booking", "reservation", "reservations", "reserve", "appointment", "appointments", "예약"]),
        ("products", ["products", "catalog", "catalogue", "상품", "제품", "카탈로그"]),
    ]

    static let roleWords: [(key: String, words: [String])] = [
        ("snake", ["snake", "뱀"]), ("food", ["food", "apple", "apples", "fruit", "먹이", "사과", "음식"]),
        ("ball", ["ball", "balls", "공"]), ("paddle", ["paddles", "paddle", "bat", "racket", "패들", "라켓"]),
        ("bricks", ["bricks", "brick", "벽돌"]), ("blocks", ["blocks", "block", "pieces", "블록", "조각"]),
        ("player", ["player", "hero", "character", "ship", "spaceship", "plane", "bird", "car", "dino", "dinosaur", "플레이어", "주인공", "캐릭터",
                    "우주선", "비행기", "새", "자동차", "공룡"]),
        ("enemy", ["enemies", "enemy", "aliens", "monsters", "obstacles", "pipes", "cactus", "적", "외계인", "몬스터", "장애물", "파이프", "선인장"]),
        ("background", ["background", "sky", "배경", "하늘"]), ("text", ["text", "font", "글자", "글씨"]),
        ("button", ["buttons", "button", "버튼"]), ("header", ["header", "navbar", "navigation", "헤더", "상단바"]),
        ("accent", ["accent", "theme colour", "theme color", "theme", "primary colour", "primary color", "main colour", "main color", "포인트 색",
                    "테마", "메인 색", "주색"]),
        ("board", ["board", "grid", "판", "보드", "격자"]), ("cards", ["cards", "card", "카드"]), ("walls", ["walls", "wall", "벽"]),
        ("coins", ["coins", "coin", "stars", "gems", "동전", "코인", "별", "보석"]), ("bullets", ["bullets", "lasers", "laser", "총알", "레이저"]),
    ]

    static let styleWords: [(key: String, words: [String])] = [
        ("retro", ["retro", "8 bit", "8bit", "arcade style", "old school", "레트로", "8비트", "고전"]),
        ("pixel", ["pixel art", "pixel", "pixelated", "픽셀", "도트"]),
        ("neon", ["neon", "glowing", "synthwave", "cyberpunk", "네온", "사이버펑크"]),
        ("minimal", ["minimalist", "minimal", "simple", "clean", "미니멀", "심플", "깔끔한", "단순한"]),
        ("cute", ["cute", "kawaii", "adorable", "귀여운", "깜찍한", "아기자기"]),
        ("dark", ["dark", "black theme", "어두운", "다크"]),
        ("light", ["light theme", "bright", "white theme", "밝은", "화이트 테마"]),
        ("pastel", ["pastel", "soft colours", "soft colors", "파스텔"]),
        ("futuristic", ["futuristic", "sci fi", "scifi", "space age", "high tech", "미래적", "미래", "sf", "첨단"]),
        ("elegant", ["elegant", "luxury", "premium", "고급스러운", "고급", "우아한", "럭셔리"]),
        ("playful", ["playful", "colorful", "colourful", "fun", "알록달록", "화려한", "재밌는", "발랄한"]),
    ]

    /// Business types: what a site for them usually holds.
    static let businesses: [(key: String, words: [String], sections: [String])] = [
        ("bakery", ["bakery", "bakeshop", "patisserie", "빵집", "베이커리", "제과점"], ["menu", "about", "location", "contact"]),
        ("cafe", ["cafe", "café", "coffee shop", "coffee", "카페", "커피숍", "커피"], ["menu", "about", "location", "contact"]),
        ("restaurant", ["restaurant", "bistro", "diner", "pizzeria", "sushi", "식당", "레스토랑", "음식점", "맛집", "피자집"], ["menu", "about", "booking", "location"]),
        ("gym", ["gym", "fitness", "yoga", "pilates", "헬스장", "헬스", "피트니스", "요가", "필라테스"], ["services", "pricing", "team", "contact"]),
        ("clinic", ["clinic", "dentist", "dental", "hospital", "doctor", "병원", "치과", "의원", "한의원"], ["services", "team", "booking", "location"]),
        ("school", ["school", "academy", "tutoring", "course", "courses", "학원", "학교", "과외", "강의"], ["services", "team", "pricing", "contact"]),
        ("hotel", ["hotel", "guesthouse", "hostel", "resort", "호텔", "펜션", "게스트하우스", "리조트"], ["gallery", "pricing", "booking", "location"]),
        ("company", ["company", "startup", "agency", "business", "firm", "회사", "스타트업", "에이전시", "기업"], ["services", "about", "testimonials", "contact"]),
        ("product", ["product", "app launch", "saas", "제품", "서비스 출시"], ["services", "pricing", "testimonials", "faq"]),
        ("event", ["wedding", "event", "conference", "party", "festival", "결혼식", "행사", "컨퍼런스", "파티", "축제"], ["about", "location", "booking", "faq"]),
        ("personal", ["personal", "resume", "cv", "myself", "개인", "이력서", "자기소개"], ["about", "gallery", "contact"]),
        ("band", ["band", "musician", "artist", "singer", "밴드", "뮤지션", "아티스트", "가수"], ["about", "gallery", "booking", "contact"]),
    ]

    // MARK: Parsing

    static func parse(_ text: String) -> ProgramBrief {
        let lex = Lexed(text)
        var b = ProgramBrief(request: text)
        b.korean = lex.korean
        let lower = " " + text.lowercased() + " "

        let templateMatches = lex.matches(templates)
        // A specific template beats the generic website one.
        if let t = templateMatches.first(where: { $0.key != "landing" }) ?? templateMatches.first {
            b.template = t.key
            b.kind = templateKind[t.key] ?? "app"
        }
        let kindMatches = lex.matches(kinds)
        if b.template == nil, let k = kindMatches.first { b.kind = k.key }
        // "a website for my bakery game shop" → explicit kind words decide between game templates and sites.
        if let t = b.template, templateKind[t] == "website", kindMatches.contains(where: { $0.key == "game" }) {
            b.kind = "game"
            b.template = nil
        }
        if b.template == "store" && kindMatches.contains(where: { $0.key == "game" }) { b.template = nil; b.kind = "game" }

        if let lang = lex.matches(languages).first {
            switch lang.key {
            case "react", "vue", "typescript": b.language = lang.key   // still runs in the browser
            default: b.language = lang.key
            }
        }

        let excluded = exclusions(lex, text: text)
        var features: [String] = []
        for m in lex.matches(featureWords) where !features.contains(m.key) { features.append(m.key) }
        b.excluded = features.filter { excluded.contains($0) }
        b.features = features.filter { !excluded.contains($0) }
        if b.features.contains("highscore") && !b.features.contains("score") { b.features.append("score") }

        if b.kind == "website" {
            for m in lex.matches(sectionWords) where !b.sections.contains(m.key) && !excluded.contains(m.key) { b.sections.append(m.key) }
            if b.template == "landing" || b.template == nil {
                if let business = lex.matches(businesses.map { ($0.key, $0.words) }).first {
                    b.subject = business.key
                    let defaults = businesses.first { $0.key == business.key }?.sections ?? []
                    for s in defaults where !b.sections.contains(s) && !excluded.contains(s) { b.sections.append(s) }
                }
            }
            if b.features.contains("cart") && b.template == "landing" { b.template = "store" }
        }
        for m in lex.matches(styleWords) where !b.styles.contains(m.key) { b.styles.append(m.key) }
        if b.features.contains("darkmode") && !b.styles.contains("dark") { b.styles.append("dark") }

        b.colors = colors(lex)
        b.numbers = numbers(text, lower: lower, lex: lex)
        b.title = title(text)
        if b.subject == nil { b.subject = subject(text, lex: lex, brief: b) }
        // Gomoku is tic-tac-toe on a bigger board with five in a row.
        if b.template == "tictactoe" && (lower.contains("gomoku") || lower.contains("five in a row") || lower.contains("connect five") || text.contains("오목")) {
            if b.numbers["grid"] == nil { b.numbers["grid"] = 15 }
            b.numbers["win"] = 5
        }
        return b
    }

    private static func exclusions(_ lex: Lexed, text: String) -> Set<String> {
        var out = Set<String>()
        let lower = text.lowercased()
        let all = featureWords + sectionWords
        for (key, words) in all {
            for w in words {
                for marker in ["without \(w)", "no \(w)", "remove the \(w)", "remove \(w)", "turn off \(w)", "turn off the \(w)", "disable \(w)",
                               "\(w) off", "get rid of the \(w)", "\(w) 없이", "\(w) 없는", "\(w) 빼", "\(w)는 빼", "\(w)은 빼", "\(w) 제거", "\(w) 끄",
                               "\(w)를 빼", "\(w)을 빼", "\(w) 없애", "\(w)를 없애", "\(w)을 없애", "\(w) 꺼"] where lower.contains(marker) {
                    out.insert(key)
                }
            }
        }
        return out
    }

    /// Colours tied to the nearest part ("blue snake", "the snake is blue", "뱀은 파란색").
    private static func colors(_ lex: Lexed) -> [String: String] {
        var out: [String: String] = [:]
        let colorMatches = lex.matches(DesignVocabulary.colors)
        let roles = lex.matches(roleWords)
        for c in colorMatches {
            var best: (key: String, distance: Int)?
            for r in roles {
                let distance: Int = r.span.start >= c.span.end ? r.span.start - c.span.end : (c.span.start - r.span.end) + 1
                guard distance <= 3 else { continue }
                if best == nil || distance < best!.distance { best = (r.key, distance) }
            }
            let role = best?.key ?? (out["main"] == nil ? "main" : "accent")
            if out[role] == nil { out[role] = c.key }
        }
        return out
    }

    private static func firstNumber(_ pattern: String, in text: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        let s = String(text[r])
        if let d = Double(s) { return d }
        if let n = DesignVocabulary.englishNumbers[s.lowercased()] { return Double(n) }
        if let n = DesignVocabulary.koreanNumbers.first(where: { $0.0 == s })?.1 { return Double(n) }
        return nil
    }

    private static func numbers(_ text: String, lower: String, lex: Lexed) -> [String: Double] {
        var n: [String: Double] = [:]
        let num = "(\\d+(?:\\.\\d+)?|one|two|three|four|five|six|seven|eight|nine|ten|twelve|twenty|하나|둘|셋|넷|다섯|여섯|일곱|여덟|아홉|열|한|두|세|네)"
        if let v = firstNumber(num + "\\s*(?:lives|life|hearts)", in: text) ?? firstNumber("(?:목숨|생명|하트|라이프)(?:은|는|이|가|을|를)?\\s*" + num, in: text) { n["lives"] = v }
        if let v = firstNumber(num + "\\s*(?:levels|stages)", in: text) ?? firstNumber("(?:레벨|스테이지|단계)(?:은|는|이|가|을|를)?\\s*" + num, in: text) { n["levels"] = v }
        if let v = firstNumber(num + "\\s*(?:questions)", in: text) ?? firstNumber("(?:문제|문항)(?:은|는|이|가|을|를)?\\s*" + num, in: text) ?? firstNumber(num + "\\s*(?:문제|문항)", in: text) { n["items"] = v }
        if let v = firstNumber(num + "\\s*(?:pairs)", in: text) { n["items"] = v }
        if let v = firstNumber(num + "\\s*(?:cards)", in: text) ?? firstNumber("카드(?:는|가)?\\s*" + num, in: text) { n["items"] = (v / 2).rounded() }
        if let v = firstNumber(num + "\\s*(?:players)", in: text) ?? firstNumber(num + "\\s*(?:인용|명)", in: text) { n["players"] = v }
        if let re = try? NSRegularExpression(pattern: "(\\d{1,2})\\s*(?:x|×|by|곱하기|\\*)\\s*(\\d{1,2})", options: [.caseInsensitive]),
           let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let r = Range(m.range(at: 1), in: text), let v = Double(text[r]) {
            n["grid"] = v
        }
        if let v = firstNumber(num + "\\s*in a row", in: text) ?? firstNumber(num + "\\s*목", in: text) { n["win"] = v }
        if let v = firstNumber("(?:first to|play to|up to|race to)\\s*" + num, in: text) ?? firstNumber("(\\d+)\\s*점(?:\\s*먼저|\\s*내기|을 먼저|이면 승리)", in: text) { n["target"] = v }
        // Time limits: "60 seconds", "2 minutes", "1분", "30초".
        if let s = firstNumber("(\\d+)\\s*(?:seconds|secs|sec|초)", in: text) { n["time"] = s }
        if let m = firstNumber("(\\d+)\\s*(?:minutes|minute|mins|min|분)", in: text) { n["time"] = (n["time"] ?? 0) + m * 60 }
        if let v = firstNumber("speed\\s*(?:of|to|=|:)?\\s*(\\d+(?:\\.\\d+)?)", in: text) ?? firstNumber("속도(?:를|는|가)?\\s*(\\d+(?:\\.\\d+)?)", in: text) {
            n["speed"] = v > 3 ? v / 5 : v
        }
        if n["speed"] == nil {
            let veryFast = ["very fast", "super fast", "really fast", "extremely fast", "아주 빠", "엄청 빠", "매우 빠", "초고속"]
            let fast = ["faster", "fast", "quick", "speedy", "빠르", "빠른", "빨리"]
            let slow = ["slower", "slow", "relaxed", "느리", "느린", "천천히"]
            if veryFast.contains(where: { lower.contains($0) }) { n["speed"] = 2 }
            else if fast.contains(where: { lower.contains(" " + $0) || lower.contains($0) && !$0.allSatisfy({ $0.isASCII }) }) { n["speed"] = 1.4 }
            else if slow.contains(where: { lower.contains(" " + $0) || lower.contains($0) && !$0.allSatisfy({ $0.isASCII }) }) { n["speed"] = 0.7 }
        }
        if ["easy", "쉬운", "쉽게", "초보"].contains(where: { lower.contains($0) }) { n["difficulty"] = 0 }
        if ["hard", "difficult", "challenging", "어려운", "어렵게", "고수"].contains(where: { lower.contains($0) }) { n["difficulty"] = 2 }
        return n
    }

    private static func title(_ text: String) -> String? {
        let patterns = ["(?:called|named|titled|title)\\s*[\"“'‘]([^\"”'’]{1,40})[\"”'’]",
                        "(?:called|named|titled)\\s+([A-Z][\\w\\- ]{1,30}?)(?:[.,!]|\\s+(?:with|that|and|where|for)\\b|$)",
                        "(?:제목|이름|타이틀)(?:은|는|을|를)?\\s*[\"“'‘]?([^\"”'’,.]{1,30}?)[\"”'’]?\\s*(?:으로|로|이라고|라고|인|$)",
                        "[\"“]([^\"”]{2,40})[\"”]"]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: []),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let r = Range(m.range(at: 1), in: text) else { continue }
            let t = String(text[r]).trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return nil
    }

    /// What a site or app is about: "a website for my bakery" → "bakery"; "빵집 홈페이지" → "빵집".
    private static func subject(_ text: String, lex: Lexed, brief: ProgramBrief) -> String? {
        let lowerText = text.lowercased()
        for marker in [" for my ", " for our ", " for a ", " for an ", " for the ", " for ", " about "] {
            guard let r = lowerText.range(of: marker) else { continue }
            var rest = String(text[r.upperBound...])
            for stop in [" with ", " that ", " which ", " where ", " in ", ",", ".", " and ", " using "] {
                if let s = rest.lowercased().range(of: stop) { rest = String(rest[..<s.lowerBound]) }
            }
            let words = rest.split(separator: " ").prefix(4).joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
            if !words.isEmpty && words.count < 40 { return words }
        }
        if lex.korean {
            // Noun right before the kind word: "빵집 홈페이지", "우리 회사 웹사이트".
            let kindWords = ["홈페이지", "웹사이트", "사이트", "웹페이지", "게임", "앱", "어플", "프로그램", "챗봇"]
            for (i, token) in lex.tokens.enumerated() where i > 0 && kindWords.contains(where: { token.hasPrefix($0) }) {
                let prev = lex.tokens[i - 1]
                let stripped = prev.replacingOccurrences(of: "의$", with: "", options: .regularExpression)
                if !["만들어", "만들어줘", "하나", "간단한", "멋진", "새로운", "우리"].contains(stripped) { return stripped }
            }
        }
        return nil
    }

    // MARK: Adjustments

    /// Merge an adjustment ("make the snake blue", "add sound", "faster", "remove the timer") into this brief.
    func refined(by edit: ProgramBrief, editText: String) -> ProgramBrief {
        var b = self
        for (role, color) in edit.colors {
            // A bare colour in an edit means the main thing ("make it red").
            b.colors[role == "main" && b.colors["main"] == nil && edit.colors.count == 1 ? "main" : role] = color
        }
        for (k, v) in edit.numbers where k != "speed" { b.numbers[k] = v }
        let lower = editText.lowercased()
        let relative = ["faster", "slower", "quicker", "빠르게", "느리게", "더 빠", "더 느", "속도를 올", "속도를 내"].contains { lower.contains($0) }
        if let s = edit.numbers["speed"] {
            if relative {
                let up = ["faster", "quicker", "빠르게", "더 빠", "속도를 올"].contains { lower.contains($0) }
                b.numbers["speed"] = ((b.numbers["speed"] ?? 1) * (up ? 1.35 : 0.72) * 100).rounded() / 100
            } else {
                b.numbers["speed"] = s
            }
        }
        for f in edit.features where !b.features.contains(f) { b.features.append(f) }
        for f in edit.excluded { b.features.removeAll { $0 == f }; if !b.excluded.contains(f) { b.excluded.append(f) } }
        b.excluded.removeAll { edit.features.contains($0) }
        for s in edit.sections where !b.sections.contains(s) { b.sections.append(s) }
        b.sections.removeAll { edit.excluded.contains($0) }
        if !edit.styles.isEmpty {
            let exclusive: Set<String> = ["dark", "light"]
            if edit.styles.contains(where: exclusive.contains) { b.styles.removeAll(where: exclusive.contains) }
            for s in edit.styles where !b.styles.contains(s) { b.styles.append(s) }
        }
        if let t = edit.title { b.title = t }
        b.request = request + " | " + editText
        return b
    }
}
