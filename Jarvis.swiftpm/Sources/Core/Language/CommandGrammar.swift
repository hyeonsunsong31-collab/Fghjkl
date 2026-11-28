import Foundation

/// Every function Jarvis can execute directly (voice and text use the same grammar).
enum CommandIntent: String, Codable, CaseIterable {
    // Assistant state
    case wake, sleep, stopSpeaking, muteMic, unmuteMic, muteVoice, unmuteVoice
    case help, showHistory, showBrain, openSettings, resumeTask, cancelTask
    case deepThinkOn, deepThinkOff, setVoice, speakFaster, speakSlower, setLanguage
    // 3D project space
    case open3D, close3D, handTrackingOn, handTrackingOff
    case createObject, generateModel, refineModel, setRenderStyle, cloneObject, deleteObject, selectObject
    case moveObject, scaleObject, rotateObject, colorObject
    case undo, redo, exportModel, saveWallpaper, clearScene, resetCamera
    // Media & web
    case playMusic, pauseMusic, resumeMusic, stopMusic, nextTrack
    case openBrowser, webSearch, openURL
    // Device
    case openApp, flashlightOn, flashlightOff, setBrightness, setVolume
    case batteryStatus, timeQuery, dateQuery, setTimer, setAlarm
    case runShortcut, systemSetting, call, message

    /// Coarse class used to teach the cortex.
    var intentClass: IntentClass {
        switch self {
        case .wake, .sleep, .stopSpeaking, .muteMic, .unmuteMic, .muteVoice, .unmuteVoice, .help, .showHistory,
             .showBrain, .openSettings, .resumeTask, .cancelTask, .deepThinkOn, .deepThinkOff, .setVoice,
             .speakFaster, .speakSlower, .setLanguage:
            return .systemControl
        case .open3D, .close3D, .handTrackingOn, .handTrackingOff, .createObject, .generateModel, .refineModel, .setRenderStyle, .cloneObject,
             .deleteObject, .selectObject, .moveObject, .scaleObject, .rotateObject, .colorObject, .undo, .redo,
             .exportModel, .saveWallpaper, .clearScene, .resetCamera:
            return .command3D
        case .playMusic, .pauseMusic, .resumeMusic, .stopMusic, .nextTrack: return .music
        case .openBrowser, .webSearch, .openURL: return .web
        case .openApp: return .appLaunch
        case .flashlightOn, .flashlightOff, .setBrightness, .setVolume, .batteryStatus, .setTimer, .setAlarm,
             .runShortcut, .systemSetting, .call, .message:
            return .deviceControl
        case .timeQuery, .dateQuery: return .question
        }
    }

    /// Actions with external side effects that need explicit confirmation.
    var requiresConfirmation: Bool {
        switch self {
        case .call, .message, .clearScene: return true
        default: return false
        }
    }
}

/// A parsed command with its parameters.
struct Command: Codable, Equatable {
    var intent: CommandIntent
    var parameters: [String: String]
    var confidence: Float
    var text: String

    subscript(_ key: String) -> String? { parameters[key] }
}

struct GrammarResult: Equatable {
    var commands: [Command]
    var language: DetectedLanguage

    var confidence: Float { commands.isEmpty ? 0 : commands.map(\.confidence).min() ?? 0 }
    var isEmpty: Bool { commands.isEmpty }
}

/// Deterministic Korean/English command grammar — the instant path that lets
/// Jarvis execute any built-in function in milliseconds without a language model.
///
/// Matching is lexical with fuzzy tolerance (edit distance on English words,
/// substring matching on Korean stems so particles/endings don't matter).
/// Compound requests ("make a red cube and clone it twice", "3D 공간 열고 큐브
/// 만들어줘") are split into clauses; clauses that don't parse are merged back.
struct CommandGrammar {
    /// Set by the app: is this the name of an app Jarvis knows how to open? A known name
    /// makes "open X" / "X 켜줘" a confident instant command instead of a guess.
    nonisolated(unsafe) static var isKnownApp: ((String) -> Bool)?


    // MARK: Lexicon

    static let shapes: [(canonical: String, words: [String])] = [
        ("cube", ["cube", "cubes", "box", "boxes", "block", "blocks", "큐브", "정육면체", "상자", "박스", "블록", "네모"]),
        ("sphere", ["sphere", "spheres", "ball", "balls", "orb", "orbs", "globe", "구체", "공", "구슬", "구를", "구 "]),
        ("cylinder", ["cylinder", "cylinders", "tube", "pillar", "column", "원기둥", "실린더", "원통", "기둥"]),
        ("cone", ["cone", "cones", "원뿔", "콘", "고깔"]),
        ("torus", ["torus", "tori", "donut", "doughnut", "ring", "rings", "토러스", "도넛", "링", "고리"]),
        ("capsule", ["capsule", "capsules", "pill", "캡슐", "알약"]),
        ("pyramid", ["pyramid", "pyramids", "피라미드", "사각뿔"]),
        ("plane", ["plane", "floor", "panel", "plate", "sheet", "평면", "판", "패널", "바닥"]),
        ("text", ["text", "label", "word", "words", "letters", "텍스트", "글자", "문구", "라벨"]),
    ]

    static let colors: [(canonical: String, words: [String])] = [
        ("red", ["red", "crimson", "scarlet", "빨간", "빨강", "붉은", "레드", "빨갛"]),
        ("orange", ["orange", "주황", "오렌지"]),
        ("yellow", ["yellow", "노란", "노랑", "옐로", "노랗"]),
        ("green", ["green", "초록", "녹색", "그린", "연두"]),
        ("cyan", ["cyan", "aqua", "turquoise", "sky blue", "청록", "시안", "하늘색", "민트"]),
        ("blue", ["blue", "navy", "파란", "파랑", "블루", "남색", "파랗"]),
        ("purple", ["purple", "violet", "magenta", "보라", "퍼플", "자주"]),
        ("pink", ["pink", "분홍", "핑크"]),
        ("white", ["white", "하얀", "흰", "화이트", "하얗"]),
        ("black", ["black", "검은", "검정", "블랙", "까만"]),
        ("gray", ["gray", "grey", "silver", "회색", "그레이", "은색", "실버"]),
        ("gold", ["gold", "golden", "금색", "골드", "황금"]),
    ]

    static let voices = ["george": ["george", "조지"], "lewis": ["lewis", "louis", "루이스"],
                         "daniel": ["daniel", "다니엘"], "fable": ["fable", "페이블"]]

    static let systemSettings: [(canonical: String, words: [String])] = [
        ("wifi", ["wi-fi", "wifi", "wireless", "와이파이"]),
        ("bluetooth", ["bluetooth", "블루투스"]),
        ("doNotDisturb", ["do not disturb", "dnd", "focus mode", "방해 금지", "방해금지", "집중 모드", "집중모드"]),
        ("darkMode", ["dark mode", "다크 모드", "다크모드", "어두운 모드"]),
        ("lightMode", ["light mode", "라이트 모드", "라이트모드", "밝은 모드"]),
        ("lowPower", ["low power", "battery saver", "저전력"]),
        ("airplaneMode", ["airplane mode", "aeroplane mode", "flight mode", "비행기 모드", "비행기모드"]),
        ("hotspot", ["hotspot", "핫스팟", "테더링"]),
        ("cellular", ["cellular", "mobile data", "셀룰러", "데이터"]),
    ]

    static let fillerWords: Set<String> = [
        "please", "can", "could", "would", "you", "will", "me", "for", "the", "a", "an", "some", "jarvis", "now",
        "just", "kindly", "go", "ahead", "and", "to", "i", "want", "like", "need", "let", "lets", "us", "my", "it",
        "this", "that", "on", "in", "of", "up", "with", "be", "is", "are", "sir", "hey", "okay", "ok", "right",
        "좀", "제발", "자비스", "지금", "부탁해", "부탁", "주세요", "해줘", "줘", "해", "할래", "해주세요", "하나", "그리고"
    ]

    // MARK: Normalised clause

    struct Clause {
        let original: String
        let lower: String
        let tokens: [String]
        let compact: String

        init(_ text: String) {
            original = text.trimmingCharacters(in: .whitespacesAndNewlines)
            var l = original.lowercased()
            for ch in ["?", "!", ",", "~", "…"] { l = l.replacingOccurrences(of: ch, with: " ") }
            lower = " " + l.split(separator: " ").joined(separator: " ") + " "
            tokens = TextEncoder.tokens(l)
            compact = l.replacingOccurrences(of: " ", with: "")
        }

        /// Does the clause contain any of the cue words?
        /// English: word/phrase boundary match (+ fuzzy for long words). Korean: substring (spaced or compact).
        func has(_ cues: [String]) -> Bool { firstHit(cues) != nil }

        func firstHit(_ cues: [String]) -> String? {
            for cue in cues {
                let c = cue.lowercased()
                if c.unicodeScalars.allSatisfy({ $0.isASCII }) {
                    if c.contains(" ") || c.contains("-") {
                        if lower.contains(" " + c + " ") || lower.contains(" " + c) && c.count > 6 { return cue }
                    } else if tokens.contains(c) || tokens.contains(where: { FuzzyMatch.approximately($0, c) }) {
                        return cue
                    }
                } else {
                    if lower.contains(c) || compact.contains(c.replacingOccurrences(of: " ", with: "")) { return cue }
                }
            }
            return nil
        }
    }

    // MARK: Parsing

    func parse(_ text: String) -> GrammarResult {
        let language = LanguageDetector.detect(text).language
        let commands = parsePieces(Self.split(text))
        // A detailed design request ("a red car with black wheels and a spoiler") is one command:
        // splitting it at "and" would scatter its details. Sentences that also ask for other
        // things ("open the 3D space and make a castle") keep their separate commands.
        let designIntents: Set<CommandIntent> = [.generateModel, .createObject, .colorObject, .scaleObject, .refineModel]
        if Self.isSingleDesignRequest(text), commands.allSatisfy({ designIntents.contains($0.intent) }),
           let whole = parseClause(Clause(text)), whole.intent == .generateModel {
            return GrammarResult(commands: [whole], language: language)
        }
        return GrammarResult(commands: commands, language: language)
    }

    private func parsePieces(_ pieces: [String]) -> [Command] {
        var commands: [Command] = []
        var pending = ""
        for piece in pieces {
            let candidate = pending.isEmpty ? piece : pending + " " + piece
            if let cmd = parseClause(Clause(piece)) {
                if !pending.isEmpty, let merged = parseClause(Clause(candidate)), merged.intent == cmd.intent {
                    commands.append(merged)
                } else {
                    if !pending.isEmpty, let prev = parseClause(Clause(pending)) { commands.append(prev) }
                    commands.append(cmd)
                }
                pending = ""
            } else if var last = commands.popLast() {
                // Unparsed fragment: attach to the previous clause if it still parses the same way.
                if let merged = parseClause(Clause(last.text + " " + piece)), merged.confidence >= last.confidence * 0.9 {
                    commands.append(merged)
                } else {
                    last.confidence *= 0.9
                    commands.append(last)
                    pending = candidate
                }
            } else {
                pending = candidate
            }
        }
        if !pending.isEmpty, commands.isEmpty, let cmd = parseClause(Clause(pending)) { commands.append(cmd) }

        // Resolve pronoun-only follow-ups ("clone it", "make it bigger") — handled by the scene resolver.
        return commands
    }

    /// Names an object to design, with no "then"/"그 다음" sequencing of separate commands.
    static func isSingleDesignRequest(_ text: String) -> Bool {
        let lower = " " + text.lowercased() + " "
        let sequencing = [" then ", " after that ", "; ", "그 다음", "그다음", "그리고 나서", "한 다음", "한 후에", "하고 나서"]
        if sequencing.contains(where: { lower.contains($0) }) { return false }
        let creating = ["make", "create", "build", "design", "generate", "draw", "model", "give me",
                        "만들", "생성", "설계", "그려", "모델링"]
        guard creating.contains(where: { lower.contains($0) }) else { return false }
        return !Lexed(text).matches(DesignVocabulary.subjects).isEmpty
    }

    /// Split into candidate clauses on conjunctions.
    static func split(_ text: String) -> [String] {
        var s = " " + text + " "
        let englishSeparators = [" and then ", " then ", " after that ", "; ", " and also ", " and "]
        let koreanSeparators = ["그리고 나서", "그리고", "그 다음에", "그다음에", "그 다음", "그다음", "그런 다음", "한 다음", "한 후에", "하고 나서", "다음에"]
        let marker = "\u{1F}"
        for sep in englishSeparators { s = s.replacingOccurrences(of: sep, with: marker, options: .caseInsensitive) }
        for sep in koreanSeparators { s = s.replacingOccurrences(of: sep, with: marker) }
        // Korean connective "-고 " after a verb stem: 열고 / 만들고 / 켜고 / 끄고 / 복제하고 …
        let connectives = ["열고 ", "만들고 ", "켜고 ", "끄고 ", "닫고 ", "복제하고 ", "삭제하고 ", "지우고 ", "틀고 ", "재생하고 ",
                           "생성하고 ", "추가하고 ", "보여주고 ", "옮기고 ", "키우고 ", "줄이고 ", "돌리고 ", "실행하고 ", "검색하고 "]
        for c in connectives {
            // Keep the verb stem (matching is stem-based), cut the clause after it.
            s = s.replacingOccurrences(of: c, with: String(c.dropLast(2)) + " " + marker)
        }
        return s.components(separatedBy: marker)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: Rules

    func parseClause(_ c: Clause) -> Command? {
        guard !c.tokens.isEmpty else { return nil }
        var best: Command?
        func consider(_ intent: CommandIntent, _ base: Float, _ params: [String: String] = [:]) {
            // Design requests are meant to be long and detailed: no penalty for extra words.
            let conf = intent == .generateModel || intent == .refineModel ? base : base * coverage(c)
            if conf > (best?.confidence ?? 0) {
                best = Command(intent: intent, parameters: params, confidence: conf, text: c.original)
            }
        }

        // Shared cue sets.
        let open = ["open", "launch", "start", "show", "bring up", "pull up", "display", "activate", "run", "go to", "enter",
                    "열어", "열기", "열", "실행", "띄워", "보여", "시작", "불러", "들어가"]
        let close = ["close", "hide", "exit", "quit", "dismiss", "leave", "닫아", "닫기", "닫", "숨겨", "종료", "나가"]
        let on = ["turn on", "switch on", "enable", "activate", "start", "on", "켜", "활성", "시작"]
        let off = ["turn off", "switch off", "disable", "deactivate", "stop", "off", "꺼", "끄", "끈", "비활성", "중지", "멈춰"]
        let create = ["create", "make", "add", "spawn", "build", "generate", "place", "put", "draw", "insert", "give me", "new", "design",
                      "만들", "생성", "추가", "놓아", "넣어", "그려", "띄워", "설계"]
        let space3D = ["3d space", "3d project", "project space", "3d workspace", "workspace", "workshop", "modelling space",
                       "modeling space", "hologram space", "design space", "3d", "lab",
                       "3d 공간", "3d공간", "3d 프로젝트", "프로젝트 공간", "모델링", "작업 공간", "작업공간", "홀로그램 공간", "3디", "3차원"]
        let hand = ["hand tracking", "hand gestures", "hand gesture", "gesture", "gestures", "hand control", "camera tracking",
                    "손 인식", "손인식", "손동작", "제스처", "핸드 트래킹", "핸드트래킹", "손 추적", "카메라 인식", "손 제스처"]
        let mic = ["mic", "microphone", "마이크"]
        let voiceNoun = ["your voice", "voice", "speech", "talking", "음성", "목소리", "말소리"]
        let music = ["music", "song", "songs", "track", "playlist", "album", "tune", "음악", "노래", "곡", "플레이리스트", "앨범"]
        let mute = ["mute", "silence", "음소거"]
        let unmute = ["unmute", "음소거 해제", "음소거해제"]

        let colorParam = Self.color(in: c)
        let shapeParam = Self.shape(in: c)
        let count = Self.count(in: c)

        // --- Wake / sleep ------------------------------------------------------
        if WakeWordMatcher().match(c.original) != nil { consider(.wake, 1.0) }
        if c.has(["go to sleep", "sleep", "stand by", "standby", "that's all", "that will be all", "goodnight", "good night",
                  "dismissed", "잘 자", "잘자", "쉬어", "대기해", "대기 모드", "슬립", "자러 가", "수고했어", "들어가 쉬어"]) {
            consider(.sleep, 0.9)
        }

        // --- Speech control ----------------------------------------------------
        if c.has(["stop talking", "stop speaking", "be quiet", "quiet", "shush", "hush", "enough", "silence please",
                  "그만 말해", "그만해", "조용히", "조용", "그만", "닥쳐", "멈춰", "됐어"]) && !c.has(music) && !c.has(["task", "작업"]) {
            consider(.stopSpeaking, c.tokens.count <= 4 ? 0.9 : 0.7)
        }
        if c.has(["stop", "wait", "hold on"]) && c.tokens.count <= 2 { consider(.stopSpeaking, 0.85) }

        if c.has(mic) {
            if c.has(unmute) || (c.has(on) && !c.has(off)) { consider(.unmuteMic, 0.9) }
            else if c.has(mute) || c.has(off) || c.has(["stop listening"]) { consider(.muteMic, 0.92) }
        }
        if c.has(["stop listening", "듣지 마", "그만 들어"]) { consider(.muteMic, 0.9) }
        if c.has(voiceNoun) || c.has(["text only", "텍스트로만", "글로만"]) {
            if c.has(unmute) || (c.has(on) && !c.has(off)) || c.has(["speak again", "다시 말"]) { consider(.unmuteVoice, 0.88) }
            else if c.has(mute) || c.has(off) || c.has(["text only", "텍스트로만", "글로만", "말하지 마", "말하지마"]) { consider(.muteVoice, 0.88) }
        }
        if c.has(["말하지 마", "말하지마", "be silent", "silent mode", "text only"]) { consider(.muteVoice, 0.86) }
        if c.has(["speak again", "talk to me again", "다시 말해", "다시 말씀"]) { consider(.unmuteVoice, 0.86) }

        if c.has(["speak faster", "talk faster", "speak more quickly", "faster please", "빨리 말", "빠르게 말", "말 빨리"]) { consider(.speakFaster, 0.9) }
        if c.has(["speak slower", "talk slower", "slow down", "speak more slowly", "천천히 말", "느리게 말", "말 천천히"]) { consider(.speakSlower, 0.9) }

        for (name, words) in Self.voices where c.has(words) && (c.has(["voice", "목소리", "음성", "use", "switch", "바꿔", "변경"])) {
            consider(.setVoice, 0.9, ["voice": name])
        }
        if c.has(["speak korean", "in korean", "switch to korean", "한국어로", "한국말로"]) { consider(.setLanguage, 0.9, ["language": "ko"]) }
        if c.has(["speak english", "in english", "switch to english", "영어로"]) { consider(.setLanguage, 0.9, ["language": "en"]) }
        if c.has(["auto language", "automatic language", "자동 언어", "언어 자동"]) { consider(.setLanguage, 0.9, ["language": "auto"]) }

        // --- Assistant panels --------------------------------------------------
        if c.has(["help", "what can you do", "your capabilities", "list commands", "commands", "functions",
                  "도움말", "뭘 할 수", "무엇을 할 수", "뭐 할 수", "기능 알려", "기능 목록", "할 수 있는", "명령어"]) {
            consider(.help, 0.88)
        }
        if c.has(["history", "logs", "log", "records", "transcript", "기록", "로그", "히스토리", "내역", "대화 기록"]) && (c.has(open) || c.tokens.count <= 3) {
            consider(.showHistory, 0.9)
        }
        if c.has(["brain", "neural core", "neurons", "neural network", "neural", "뇌", "신경망", "뉴런", "신경 코어"]) && (c.has(open) || c.tokens.count <= 3) {
            consider(.showBrain, 0.9)
        }
        if c.has(["settings", "preferences", "설정", "환경설정", "환경 설정"]) && !c.hasAnySystemSetting {
            consider(.openSettings, c.has(open) || c.tokens.count <= 2 ? 0.9 : 0.6)
        }
        if c.has(["resume", "continue the task", "carry on", "pick up where", "재개", "이어서 해", "계속 진행", "계속해", "하던 작업"]) && !c.has(music) {
            consider(.resumeTask, 0.86)
        }
        if c.has(["cancel", "abort", "never mind", "nevermind", "forget it", "취소", "관둬", "그만둬"]) && !c.has(["undo", "실행 취소", "실행취소"]) {
            consider(.cancelTask, 0.85)
        }
        let deep = ["deep think", "deep thinking", "deep mode", "deep thought", "think harder", "think deeply",
                    "심층 사고", "심층사고", "깊게 생각", "딥씽크", "딥 씽크", "깊이 생각"]
        if c.has(deep) {
            if c.has(off) && !c.has(["think harder"]) { consider(.deepThinkOff, 0.92) } else { consider(.deepThinkOn, 0.92) }
        }

        // --- 3D space -----------------------------------------------------------
        if c.has(space3D) && !c.has(["export", "내보내"]) {
            if c.has(close) || (c.has(off) && !c.has(on)) { consider(.close3D, 0.93) }
            else if c.has(open) || c.has(on) || c.tokens.count <= 3 { consider(.open3D, 0.94) }
        }
        if c.has(hand) {
            if c.has(off) || c.has(close) { consider(.handTrackingOff, 0.94) }
            else { consider(.handTrackingOn, c.has(on) || c.has(open) ? 0.94 : 0.75) }
        }

        let scaleCue = c.has(["bigger", "larger", "smaller", "twice as", "as big", "as large", "times bigger", "크게", "작게", "키워", "줄여"])
        let isCreate = c.has(create) && !(scaleCue && c.has(["make", "만들"]) && Self.count(in: c) == nil && !c.has(["new", "another", "새"]))

        // --- Detailed designs and refinements of the design in the workspace ---------
        let designLex = Lexed(c.original)
        let designSubjects = designLex.matches(DesignVocabulary.subjects)
        let designParts = designLex.matches(DesignVocabulary.components)
        let subjectOnly = designSubjects.filter { s in !designParts.contains { $0.span == s.span } }
        let editCue = c.has(["add", "attach", "put on", "remove", "delete", "take off", "get rid of", "change", "paint", "replace", "swap",
                             "more", "fewer", "bigger", "smaller", "larger", "longer", "shorter", "taller", "thicker", "thinner",
                             "make the", "make its", "make it", "turn the", "give it", "give the", "without",
                             "추가", "달아", "붙여", "빼", "없애", "제거", "떼어", "바꿔", "변경", "칠해", "크게", "작게", "키워", "줄여", "늘려",
                             "길게", "짧게", "두껍게", "얇게", "더 달아", "하나 더"])
        let definite: Bool = designLex.korean
            ? (!c.has(["만들", "생성", "설계", "그려"]) || c.has(["바꿔", "변경", "칠해", "추가", "빼", "없애", "제거", "달아"]))
            : subjectOnly.contains { (m: Match) -> Bool in m.span.start > 0 && ["the", "my", "this", "that", "your", "its", "our"].contains(designLex.tokens[m.span.start - 1]) }
        let refining = !designParts.isEmpty && editCue && !c.has(["new", "another", "새로운", "새 "]) && (subjectOnly.isEmpty || definite)
        if refining {
            consider(.refineModel, 0.94, ["request": c.original])
        }
        let style = c.has(["hologram mode", "holographic mode", "hologram style", "as holograms", "홀로그램 모드", "홀로그램 스타일", "홀로그램으로 보여"])
            ? "hologram"
            : (c.has(["realistic mode", "solid mode", "real materials", "realistic materials", "실사 모드", "실제 재질", "재질 모드", "현실적으로 보여"]) ? "solid" : nil)
        if let style { consider(.setRenderStyle, 0.93, ["style": style]) }

        if isCreate && !refining && !designSubjects.isEmpty && !c.has(space3D.filter { $0 != "3d" && $0 != "3디" }) {
            let description = Self.residue(c, removing: create + ["3d", "model", "hologram", "object", "모델", "홀로그램", "오브젝트", "객체", "a", "an", "the"])
            consider(.generateModel, 0.93, ["description": description, "request": c.original])
        } else if isCreate, let shape = shapeParam {
            var p: [String: String] = ["shape": shape, "count": String(count ?? 1)]
            if let col = colorParam { p["color"] = col }
            if let size = Self.sizeAdjective(in: c) { p["size"] = size }
            if shape == "text", let q = Self.quoted(c.original) ?? Self.afterKeyword(c, ["saying", "that says", "reading"]) { p["content"] = q }
            consider(.createObject, 0.95, p)
        } else if isCreate && !c.has(space3D) && !c.has(["timer", "alarm", "타이머", "알람", "note", "메모", "event", "일정", "reminder", "미리 알림", "shortcut", "단축어", "playlist"]) {
            let description = Self.residue(c, removing: create + ["3d", "model", "hologram", "object", "모델", "홀로그램", "오브젝트", "객체", "a", "an"])
            if !description.isEmpty && !refining {
                consider(.generateModel, 0.8, ["description": description, "request": c.original])
            }
        }

        if c.has(["clone", "duplicate", "copy", "replicate", "one more", "another one", "복제", "복사", "클론", "하나 더", "똑같은"]) && !c.has(["text", "link", "링크", "url"]) {
            var p = Self.targetParameters(c, shape: shapeParam, color: colorParam)
            p["count"] = String(Self.repetitions(in: c) ?? 1)
            consider(.cloneObject, 0.93, p)
        }
        if c.has(["delete", "remove", "destroy", "erase", "get rid of", "discard", "삭제", "지워", "지우", "없애", "제거"]) {
            if c.has(["everything", "all", "all objects", "the whole scene", "전부", "모두", "다 지워", "전체"]) {
                consider(.clearScene, 0.9)
            } else if !c.has(["history", "기록", "file", "파일"]) {
                consider(.deleteObject, 0.9, Self.targetParameters(c, shape: shapeParam, color: colorParam))
            }
        }
        if c.has(["clear", "reset scene", "clear the scene", "clear scene", "초기화"]) && c.has(space3D + ["scene", "장면", "everything", "all", "전부", "모두"]) {
            consider(.clearScene, 0.88)
        }
        if c.has(["select", "pick", "choose", "highlight", "focus on", "선택", "골라", "집어"]) {
            consider(.selectObject, 0.88, Self.targetParameters(c, shape: shapeParam, color: colorParam))
        }

        let directions: [(String, [String])] = [
            ("left", ["left", "왼쪽", "좌측", "왼편"]), ("right", ["right", "오른쪽", "우측", "오른편"]),
            ("up", ["up", "upward", "upwards", "higher", "위로", "위쪽", "올려"]), ("down", ["down", "downward", "lower", "아래로", "아래쪽", "내려"]),
            ("forward", ["forward", "closer", "towards me", "앞으로", "가까이", "당겨"]), ("back", ["back", "backward", "away", "further", "뒤로", "멀리", "밀어"]),
        ]
        let levelNouns = ["brightness", "volume", "밝기", "볼륨", "음량", "소리"]
        if c.has(["move", "shift", "push", "slide", "drag", "bring", "nudge", "옮겨", "이동", "움직", "밀어", "당겨", "올려", "내려"]) && !c.has(levelNouns) {
            var p = Self.targetParameters(c, shape: shapeParam, color: colorParam)
            if let dir = directions.first(where: { c.has($0.1) })?.0 { p["direction"] = dir }
            if let meters = Self.distanceMeters(in: c) { p["amount"] = String(meters) }
            if p["direction"] != nil { consider(.moveObject, 0.9, p) }
        }

        let bigger = ["bigger", "larger", "enlarge", "grow", "scale up", "increase the size", "as big", "as large", "twice as", "times as",
                      "크게", "키워", "확대", "늘려", "커지게"]
        let smaller = ["smaller", "shrink", "scale down", "reduce the size", "작게", "줄여", "축소", "작아지게"]
        if (c.has(bigger) || c.has(smaller) || c.has(["scale", "resize", "times bigger", "배로", "배 크기", "크기"])) && !c.has(levelNouns + ["font", "글씨"]) {
            var p = Self.targetParameters(c, shape: shapeParam, color: colorParam)
            p["factor"] = String(Self.scaleFactor(in: c, bigger: c.has(bigger), smaller: c.has(smaller)))
            consider(.scaleObject, 0.9, p)
        }
        if c.has(["rotate", "spin", "twist", "turn around", "회전", "돌려"]) {
            var p = Self.targetParameters(c, shape: shapeParam, color: colorParam)
            p["degrees"] = String(Self.degrees(in: c) ?? 45)
            if c.has(["x axis", "x-axis", "x축", "pitch", "앞뒤로"]) { p["axis"] = "x" }
            else if c.has(["z axis", "z-axis", "z축", "roll"]) { p["axis"] = "z" }
            else { p["axis"] = "y" }
            consider(.rotateObject, 0.9, p)
        }
        if let col = colorParam, !isCreate,
           c.has(["color", "colour", "paint", "make it", "turn it", "change", "색", "칠해", "바꿔", "변경", "으로 해"]) {
            var p = Self.targetParameters(c, shape: shapeParam, color: nil)
            p["color"] = col
            consider(.colorObject, 0.9, p)
        }
        if c.has(["undo", "revert", "go back a step", "되돌려", "실행 취소", "실행취소", "언두", "방금 거 취소"]) { consider(.undo, 0.93) }
        if c.has(["redo", "다시 실행", "재실행", "리두"]) { consider(.redo, 0.93) }
        if c.has(["export", "save as usdz", "usdz", "save the model", "save model", "save the project", "내보내", "익스포트", "모델 저장", "프로젝트 저장"]) {
            consider(.exportModel, 0.9, ["format": c.has(["obj"]) ? "obj" : "usdz"])
        }
        if c.has(["wallpaper", "background", "lock screen", "home screen", "배경화면", "배경 화면", "바탕화면", "바탕 화면", "잠금화면", "잠금 화면"]) {
            consider(.saveWallpaper, c.has(["set", "save", "make", "use", "설정", "저장", "만들", "지정", "으로"]) ? 0.9 : 0.7)
        }
        if c.has(["reset view", "reset the view", "reset camera", "reset the camera", "center view", "center the view", "centre the view",
                  "centre view", "recenter", "시점 초기화", "카메라 초기화", "뷰 초기화", "화면 가운데"]) {
            consider(.resetCamera, 0.92)
        }

        // --- Music ----------------------------------------------------------------
        let play = ["play", "put on", "queue", "listen to", "start playing", "틀어", "재생", "들려", "플레이"]
        if c.has(play) && !c.has(["video", "영상", "동영상"]) || (c.has(music) && c.has(["틀", "들려", "재생", "켜"]) && !c.has(off)) {
            // Keep the user's own words for the song ("Shape of You" must not lose "of you").
            let query = MusicQuery.extract(from: c.original) ?? ""
            if c.has(play) || c.has(music) {
                consider(.playMusic, query.isEmpty ? 0.85 : 0.92, query.isEmpty ? [:] : ["query": query])
            }
        }
        if c.has(["pause", "hold the music", "일시정지", "일시 정지", "잠깐 멈춰"]) { consider(.pauseMusic, 0.92) }
        if c.has(music) && c.has(["stop", "멈춰", "꺼", "그만", "정지", "끄"]) { consider(.stopMusic, 0.93) }
        if c.has(["resume", "unpause", "keep playing", "다시 재생", "이어서 재생", "계속 재생"]) && (c.has(music) || c.tokens.count <= 2) {
            consider(.resumeMusic, 0.9)
        }
        if c.has(["next song", "next track", "skip", "skip this", "다음 곡", "다음 노래", "넘겨", "스킵"]) { consider(.nextTrack, 0.92) }

        // --- Web --------------------------------------------------------------------
        if c.has(["browser", "web browser", "internet", "브라우저", "인터넷", "웹 브라우저"]) && (c.has(open) || c.tokens.count <= 3) {
            consider(.openBrowser, 0.9)
        }
        if let url = Self.url(in: c.original) { consider(.openURL, 0.95, ["url": url]) }
        let search = ["search for", "search", "google", "look up", "find information", "검색", "찾아봐", "찾아 봐", "찾아줘"]
        if c.has(search) && !c.has(["file", "파일", "contact", "연락처"]) {
            let q = Self.residue(c, removing: search + ["on the web", "online", "on google", "the internet", "about", "인터넷에서", "웹에서", "에 대해", "좀", "을", "를"])
            if !q.isEmpty { consider(.webSearch, 0.9, ["query": q]) }
        }

        // --- Device -------------------------------------------------------------------
        if c.has(["flashlight", "torch", "flash light", "손전등", "플래시", "후레쉬", "플래쉬"]) {
            if c.has(off) { consider(.flashlightOff, 0.95) } else { consider(.flashlightOn, 0.93) }
        }
        if c.has(["brightness", "screen light", "밝기", "화면 밝기"]) || c.has(["brighter", "dimmer", "더 밝게", "더 어둡게", "어둡게", "밝게"]) && !c.has(space3D) {
            consider(.setBrightness, 0.9, Self.levelParameters(c, up: ["brighter", "up", "increase", "higher", "밝게", "올려", "높여"], down: ["dimmer", "darker", "down", "decrease", "lower", "어둡게", "내려", "낮춰"]))
        }
        if c.has(["volume", "loudness", "볼륨", "음량", "소리 크기"]) || c.has(["louder", "quieter", "더 크게", "소리 키워", "소리 줄여"]) {
            consider(.setVolume, 0.9, Self.levelParameters(c, up: ["louder", "up", "increase", "higher", "키워", "올려", "크게", "높여"], down: ["quieter", "down", "decrease", "lower", "softer", "줄여", "내려", "작게", "낮춰"]))
        }
        if c.has(["battery", "charge level", "배터리", "충전량", "잔량"]) { consider(.batteryStatus, 0.92) }
        if c.has(["what time", "the time", "current time", "time is it", "몇 시", "몇시", "현재 시간", "지금 시간"]) { consider(.timeQuery, 0.93) }
        if c.has(["what's the date", "what is the date", "today's date", "what day", "날짜", "며칠", "무슨 요일", "몇 월 며칠"]) { consider(.dateQuery, 0.93) }
        if c.has(["timer", "countdown", "타이머"]) {
            var p: [String: String] = [:]
            if let d = NumberParsing.duration(in: c.original) { p["seconds"] = String(Int(d)) }
            consider(.setTimer, p.isEmpty ? 0.7 : 0.94, p)
        }
        if c.has(["alarm", "wake me", "알람", "깨워"]) && !c.has(["jarvis"]) {
            var p: [String: String] = [:]
            if let t = NumberParsing.clockTime(in: c.original) { p["hour"] = String(t.hour); p["minute"] = String(t.minute) }
            consider(.setAlarm, p.isEmpty ? 0.7 : 0.94, p)
        }
        if c.has(["shortcut", "단축어"]) && c.has(["run", "execute", "start", "실행", "돌려"]) {
            let name = Self.quoted(c.original) ?? Self.residue(c, removing: ["run", "execute", "start", "the", "shortcut", "called", "named", "단축어", "실행", "해줘", "돌려", "을", "를"])
            if !name.isEmpty { consider(.runShortcut, 0.92, ["name": name]) }
        }
        if let setting = Self.systemSettings.first(where: { c.has($0.words) }) {
            var value = c.has(off) ? "off" : (c.has(on) ? "on" : "toggle")
            if setting.canonical == "darkMode" || setting.canonical == "lightMode" { value = setting.canonical == "darkMode" ? (c.has(off) ? "off" : "on") : (c.has(off) ? "on" : "off") }
            consider(.systemSetting, 0.92, ["setting": setting.canonical == "lightMode" ? "darkMode" : setting.canonical, "value": value])
        }
        if c.has(["call", "phone", "ring", "dial", "전화"]) && !c.has(["called", "named", "shortcut"]) {
            let who = Self.residue(c, removing: ["call", "phone", "ring", "dial", "give", "a", "전화", "걸어", "해줘", "해", "한테", "에게", "께", "좀"])
            if !who.isEmpty { consider(.call, 0.88, ["contact": who]) }
        }
        if c.has(["send a message", "send a text", "text", "message", "sms", "문자", "메시지", "카톡 보내"]) && c.has(["send", "text", "tell", "message", "보내", "전해", "문자", "메시지"]) && !c.has(["text only", "텍스트"]) {
            var p: [String: String] = [:]
            if let q = Self.quoted(c.original) { p["body"] = q }
            if let to = Self.recipient(in: c) { p["contact"] = to }
            if let body = Self.afterKeyword(c, ["saying", "that says", "that", "라고"]) , p["body"] == nil { p["body"] = body }
            consider(.message, p["contact"] == nil ? 0.65 : 0.88, p)
        }

        // --- Open app (lowest priority among "open") ---------------------------------
        let launch = ["켜", "실행", "launch"]
        if (c.has(open) || c.has(launch)) && best == nil {
            let app = Self.residue(c, removing: open + launch + ["app", "application", "the", "앱", "어플", "애플리케이션", "을", "를", "좀", "줘", "해줘"])
            if !app.isEmpty {
                let known: Bool = Self.isKnownApp?(app) ?? false
                consider(.openApp, known ? 0.93 : 0.8, ["app": app])
            }
        }
        return best
    }

    // MARK: Parameter helpers

    /// Fraction of tokens accounted for by cue words/fillers (penalises long free-form requests).
    func coverage(_ c: Clause) -> Float {
        let n = c.tokens.count
        if n <= 4 { return 1 }
        let filler = c.tokens.filter { Self.fillerWords.contains($0) }.count
        let content = n - filler
        return content <= 6 ? 1 : max(0.7, 1 - Float(content - 6) * 0.04)
    }

    static func shape(in c: Clause) -> String? {
        for (canonical, words) in shapes {
            for w in words {
                if w == "구 " || w == "구를" {
                    if c.lower.contains(" 구 ") || c.lower.contains(" 구를") || c.lower.contains(" 구가") || c.lower.contains(" 구하나") { return canonical }
                    continue
                }
                if c.has([w]) { return canonical }
            }
        }
        return nil
    }

    static func color(in c: Clause) -> String? {
        colors.first { c.has($0.words) }?.canonical
    }

    static func count(in c: Clause) -> Int? {
        if let k = NumberParsing.koreanCount(in: c.original) { return Int(k) }
        for (i, t) in c.tokens.enumerated() {
            if let d = Int(t), d > 0, d <= 50 {
                // Avoid "3d" and distances ("3 metres").
                if i + 1 < c.tokens.count, ["metre", "metres", "meter", "meters", "m", "cm", "centimetres", "degrees", "percent", "times"].contains(c.tokens[i + 1]) { continue }
                return d
            }
            if let v = NumberParsing.englishNumbers[t], v >= 1, v <= 50, v == v.rounded(), !["a", "an", "once", "twice", "thrice", "double", "triple", "single"].contains(t) {
                return Int(v)
            }
        }
        return nil
    }

    static func repetitions(in c: Clause) -> Int? {
        if c.has(["twice", "two times", "두 번", "두번", "2번"]) { return 2 }
        if c.has(["thrice", "three times", "세 번", "세번", "3번"]) { return 3 }
        let tokens = c.tokens
        for (i, t) in tokens.enumerated() where i + 1 < tokens.count && tokens[i + 1].hasPrefix("time") {
            if let d = Int(t) { return d }
            if let v = NumberParsing.englishNumbers[t] { return Int(v) }
        }
        if let k = NumberParsing.koreanCount(in: c.original) { return Int(k) }
        return count(in: c)
    }

    static func sizeAdjective(in c: Clause) -> String? {
        if c.has(["huge", "giant", "enormous", "massive", "거대한", "엄청 큰", "아주 큰"]) { return "2.5" }
        if c.has(["big", "large", "큰", "크게"]) { return "1.6" }
        if c.has(["tiny", "아주 작은", "조그만", "조그마한"]) { return "0.4" }
        if c.has(["small", "little", "작은", "작게"]) { return "0.65" }
        return nil
    }

    static func ordinal(in c: Clause) -> String? {
        let table: [(String, [String])] = [
            ("1", ["first", "1st", "첫 번째", "첫번째", "첫째"]), ("2", ["second", "2nd", "두 번째", "두번째", "둘째"]),
            ("3", ["third", "3rd", "세 번째", "세번째", "셋째"]), ("4", ["fourth", "4th", "네 번째", "네번째"]),
            ("5", ["fifth", "5th", "다섯 번째", "다섯번째"]), ("last", ["last", "latest", "newest", "마지막", "최근", "방금"]),
        ]
        return table.first { c.has($0.1) }?.0
    }

    /// Descriptor of the object a command refers to.
    static func targetParameters(_ c: Clause, shape: String?, color: String?) -> [String: String] {
        var p: [String: String] = [:]
        if let s = shape { p["targetShape"] = s }
        if let col = color { p["targetColor"] = col }
        if let o = ordinal(in: c) { p["ordinal"] = o }
        if c.has(["all", "every", "everything", "전부", "모두", "다"]) && c.has(["all", "every", "전부", "모두"]) { p["scope"] = "all" }
        if p.isEmpty { p["target"] = "current" } // "it", "this", "그거", or the current selection
        return p
    }

    static func scaleFactor(in c: Clause, bigger: Bool, smaller: Bool) -> Double {
        if c.has(["double", "twice as", "two times", "2x", "두 배", "두배", "2배"]) { return 2 }
        if c.has(["triple", "three times", "3x", "세 배", "세배", "3배"]) { return 3 }
        if c.has(["half", "절반", "반으로"]) { return 0.5 }
        if let pct = NumberParsing.percentage(in: c.original) { return bigger || !smaller ? 1 + pct / 100 : max(0.05, 1 - pct / 100) }
        for (i, t) in c.tokens.enumerated() where i + 1 < c.tokens.count && (c.tokens[i + 1] == "times" || c.tokens[i + 1] == "x") {
            if let d = Double(t) { return smaller ? 1 / max(d, 1) : d }
        }
        if let k = NumberParsing.koreanCount(in: c.original), c.compact.contains("배") { return smaller ? 1 / max(k, 1) : k }
        let much = c.has(["much", "a lot", "way", "훨씬", "많이", "아주"])
        if smaller { return much ? 0.5 : 0.67 }
        return much ? 2 : 1.5
    }

    static func degrees(in c: Clause) -> Double? {
        if c.has(["quarter turn", "90", "직각"]) { return 90 }
        if c.has(["half turn", "180", "반 바퀴", "반바퀴"]) { return 180 }
        if c.has(["full turn", "360", "한 바퀴", "한바퀴"]) { return 360 }
        if c.has(["degrees", "degree", "도"]) { return NumberParsing.firstDigits(in: c.original) ?? NumberParsing.sinoNumber(in: c.compact) }
        return nil
    }

    static func distanceMeters(in c: Clause) -> Double? {
        guard let v = NumberParsing.firstDigits(in: c.original) else {
            if c.has(["a little", "slightly", "a bit", "조금", "살짝"]) { return 0.1 }
            if c.has(["a lot", "far", "많이", "멀리"]) { return 0.6 }
            return nil
        }
        if c.has(["cm", "centimetre", "centimetres", "centimeter", "centimeters", "센티", "센치"]) { return v / 100 }
        if c.has(["mm", "millimetre", "밀리"]) { return v / 1000 }
        return v
    }

    static func levelParameters(_ c: Clause, up: [String], down: [String]) -> [String: String] {
        if let pct = NumberParsing.percentage(in: c.original) { return ["level": String(min(100, max(0, pct)) / 100)] }
        if c.has(["max", "maximum", "full", "최대", "가장 밝게", "끝까지"]) { return ["level": "1.0"] }
        if c.has(["min", "minimum", "lowest", "최소", "가장 어둡게"]) { return ["level": "0.0"] }
        if c.has(["half", "절반", "중간"]) { return ["level": "0.5"] }
        if c.has(down) { return ["delta": "-0.2"] }
        if c.has(up) { return ["delta": "0.2"] }
        return ["delta": "0.2"]
    }

    static func quoted(_ text: String) -> String? {
        for (open, close) in [("\"", "\""), ("“", "”"), ("'", "'"), ("‘", "’"), ("「", "」")] {
            if let a = text.range(of: open), let b = text.range(of: close, range: a.upperBound..<text.endIndex) {
                let q = String(text[a.upperBound..<b.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !q.isEmpty { return q }
            }
        }
        return nil
    }

    static func afterKeyword(_ c: Clause, _ keywords: [String]) -> String? {
        for k in keywords {
            if let r = c.original.range(of: " " + k + " ", options: .caseInsensitive) {
                let rest = String(c.original[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if !rest.isEmpty { return rest }
            }
            if k == "라고", let r = c.original.range(of: "라고") {
                let before = String(c.original[..<r.lowerBound])
                let body = before.split(separator: " ").suffix(6).joined(separator: " ")
                if !body.isEmpty { return body }
            }
        }
        return nil
    }

    static func recipient(in c: Clause) -> String? {
        let tokens = c.original.split(separator: " ").map(String.init)
        for (i, t) in tokens.enumerated() {
            if t.lowercased() == "to", i + 1 < tokens.count { return tokens[i + 1].trimmingCharacters(in: .punctuationCharacters) }
            for particle in ["한테", "에게", "께"] where t.hasSuffix(particle) && t.count > particle.count {
                return String(t.dropLast(particle.count))
            }
        }
        let lowerTokens = tokens.map { $0.lowercased() }
        if let i = lowerTokens.firstIndex(where: { $0 == "text" || $0 == "message" }), i + 1 < tokens.count,
           !["a", "the", "to"].contains(lowerTokens[i + 1]) {
            return tokens[i + 1].trimmingCharacters(in: .punctuationCharacters)
        }
        return nil
    }

    static func url(in text: String) -> String? {
        for token in text.split(separator: " ") {
            let t = String(token).trimmingCharacters(in: CharacterSet(charactersIn: ",.!?\"'()"))
            if t.lowercased().hasPrefix("http://") || t.lowercased().hasPrefix("https://") { return t }
            if t.lowercased().hasPrefix("www.") { return "https://" + t }
            let tlds = [".com", ".net", ".org", ".io", ".co.kr", ".kr", ".co.uk", ".dev", ".ai", ".app"]
            if tlds.contains(where: { t.lowercased().hasSuffix($0) }), !t.contains("@"), t.count > 4 { return "https://" + t }
        }
        return nil
    }

    /// Remove cue words, fillers and Korean verb endings; what remains is the free-text argument.
    static func residue(_ c: Clause, removing cues: [String]) -> String {
        var text = " " + c.original.lowercased() + " "
        for ch in ["?", "!", ",", ".", "~"] { text = text.replacingOccurrences(of: ch, with: " ") }
        // Longest cues first so phrases are removed before their parts.
        for cue in cues.sorted(by: { $0.count > $1.count }) {
            let lc = cue.lowercased()
            if lc.unicodeScalars.allSatisfy({ $0.isASCII }) {
                text = text.replacingOccurrences(of: " " + lc + " ", with: " ")
            } else {
                text = text.replacingOccurrences(of: lc, with: " ")
            }
        }
        var words = text.split(separator: " ").map(String.init)
        words = words.filter { !fillerWords.contains($0) }
        // Strip Korean endings/particles from the last word(s).
        let endings = ["해주세요", "해줄래", "해줘요", "해줘", "해봐", "해라", "할래", "주세요", "줘요", "줘", "해", "을", "를", "좀", "어줘", "어", "아줘", "줄래"]
        if var last = words.last {
            var changed = true
            while changed {
                changed = false
                for e in endings where last.hasSuffix(e) && last.count > e.count {
                    last = String(last.dropLast(e.count)); changed = true; break
                }
            }
            words[words.count - 1] = last
        }
        words = words.map { w in
            var x = w
            for p in ["을", "를"] where x.hasSuffix(p) && x.count > 1 && Hangul.hangulRatio(x) > 0 { x = String(x.dropLast()) }
            return x
        }
        return words.filter { !$0.isEmpty && !endings.contains($0) }.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Keep "X by Artist" queries intact when "by" was stripped as a filler.
    static func restoreArtistPreposition(_ c: Clause, _ query: String) -> String {
        guard c.tokens.contains("by"), !query.contains(" by ") else { return query }
        let parts = c.original.lowercased().components(separatedBy: " by ")
        guard parts.count == 2 else { return query }
        let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let title = query.replacingOccurrences(of: artist, with: "").trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? artist : "\(title) by \(artist)"
    }
}

extension CommandGrammar.Clause {
    var hasAnySystemSetting: Bool { CommandGrammar.systemSettings.contains { has($0.words) } }
}
