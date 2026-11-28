import Foundation

/// A generated product: its files and what of the request it covers.
struct ProgramBuild {
    var files: [String: String]
    var entry: String
    var title: String
    var template: String
    var kind: String
    var handled: [String]
    var unhandled: [String]
    var howTo: String
}

struct TemplateInfo {
    let id: String
    let kind: String
    let nameEN: String
    let nameKO: String
    /// Request features this template implements (beyond the ones every product has).
    let features: Set<String>
    /// On-screen buttons for touch screens (games).
    let pad: [String]
    let controlsEN: String
    let controlsKO: String
    let defaults: [String: Double]
}

/// Tested, parametric templates that turn a brief into a working product without a language
/// model. Each honours colours, speed, lives, levels, timers, sound and the other options it lists,
/// and exposes `window.__game.selfTest()` (games) or `window.__app.selfTest()` (apps) for verification.
enum ProgramLibrary {
    /// Every product has these (kit or page features).
    static let universal: Set<String> = ["sound", "highscore", "score", "pause", "touch", "fullscreen", "darkmode", "menu", "animation",
                                         "responsive", "particles"]

    static let catalog: [TemplateInfo] = [
        TemplateInfo(id: "snake", kind: "game", nameEN: "Snake", nameKO: "스네이크", features: ["levels", "lives", "timer", "powerups", "enemies", "music"],
                     pad: ["left", "up", "down", "right"], controlsEN: "Arrow keys / WASD or swipe to steer · P pause",
                     controlsKO: "방향키 / WASD 또는 스와이프로 조종 · P 일시정지", defaults: ["grid": 20, "lives": 1]),
        TemplateInfo(id: "breakout", kind: "game", nameEN: "Brick Breaker", nameKO: "벽돌깨기", features: ["levels", "lives", "powerups", "music"],
                     pad: ["left", "action", "right"], controlsEN: "← → or drag to move · Space / tap to launch · P pause",
                     controlsKO: "← → 또는 드래그로 이동 · 스페이스 / 탭으로 발사 · P 일시정지", defaults: ["lives": 3]),
        TemplateInfo(id: "pong", kind: "game", nameEN: "Paddle Duel", nameKO: "패들 대결", features: ["twoplayer", "ai", "difficulty", "music"],
                     pad: ["up", "down"], controlsEN: "↑ ↓ or drag · two players: W/S and ↑/↓", controlsKO: "↑ ↓ 또는 드래그 · 2인용: W/S 와 ↑/↓",
                     defaults: ["target": 7]),
        TemplateInfo(id: "hopper", kind: "game", nameEN: "Sky Hopper", nameKO: "스카이 호퍼", features: ["lives", "powerups", "difficulty", "music"],
                     pad: ["action"], controlsEN: "Space, click or tap to flap", controlsKO: "스페이스, 클릭 또는 탭으로 날갯짓", defaults: ["lives": 1]),
        TemplateInfo(id: "shooter", kind: "game", nameEN: "Star Defender", nameKO: "스타 디펜더",
                     features: ["levels", "lives", "powerups", "boss", "enemies", "difficulty", "music"],
                     pad: ["left", "action", "right"], controlsEN: "← → or drag to move · hold Space or touch to fire · P pause",
                     controlsKO: "← → 또는 드래그로 이동 · 스페이스를 누르거나 화면을 눌러 발사 · P 일시정지", defaults: ["lives": 3]),
        TemplateInfo(id: "runner", kind: "game", nameEN: "Dash Runner", nameKO: "대시 러너", features: ["lives", "powerups", "enemies", "music"],
                     pad: ["down", "action"], controlsEN: "Space, ↑ or tap to jump · ↓ to duck · P pause",
                     controlsKO: "스페이스, ↑ 또는 탭으로 점프 · ↓ 로 숙이기 · P 일시정지", defaults: ["lives": 1]),
        TemplateInfo(id: "dodge", kind: "game", nameEN: "Star Dodge", nameKO: "스타 닷지", features: ["lives", "timer", "enemies", "music"],
                     pad: ["left", "right"], controlsEN: "← → or drag to move · P pause", controlsKO: "← → 또는 드래그로 이동 · P 일시정지",
                     defaults: ["lives": 3]),
        TemplateInfo(id: "platformer", kind: "game", nameEN: "Pixel Quest", nameKO: "픽셀 퀘스트", features: ["levels", "lives", "enemies", "music"],
                     pad: ["left", "right", "action"], controlsEN: "← → to run · Space / ↑ to jump (hold for higher) · P pause",
                     controlsKO: "← → 로 달리기 · 스페이스 / ↑ 로 점프 (길게 누르면 더 높이) · P 일시정지", defaults: ["lives": 3, "levels": 3]),
    ]

    static func info(_ id: String) -> TemplateInfo? { catalog.first { $0.id == id } }

    /// Can a template build this request? (Web products only; other languages go to the coding agent.)
    static func canBuild(_ b: ProgramBrief) -> Bool {
        guard let t = b.template, info(t) != nil else { return false }
        return ["web", "javascript", "html"].contains(b.language) || (b.language == "python" && pythonTemplates.contains(t))
    }

    static let pythonTemplates: Set<String> = []

    static func build(_ b: ProgramBrief) -> ProgramBuild? {
        guard canBuild(b), let t = b.template, let info = info(t) else { return nil }
        let title = b.title ?? defaultTitle(info, b)
        var files: [String: String] = [:]
        switch info.kind {
        case "game":
            guard let code = gameCode(t) else { return nil }
            files["/index.html"] = JarvisGameKit.html(title: title, korean: b.korean, controls: b.korean ? info.controlsKO : info.controlsEN, pad: info.pad)
            files["/style.css"] = JarvisGameKit.css
            files["/kit.js"] = JarvisGameKit.js
            files["/config.js"] = config(b, info: info, title: title)
            files["/game.js"] = code
        default:
            return nil
        }
        let requested = b.features.filter { !universal.contains($0) }
        let handled = b.features.filter { universal.contains($0) || info.features.contains($0) }
        let unhandled = requested.filter { !info.features.contains($0) }
        files["/README.md"] = readme(info, b, title: title, handled: handled, unhandled: unhandled)
        return ProgramBuild(files: files, entry: "/index.html", title: title, template: t, kind: info.kind, handled: handled, unhandled: unhandled,
                            howTo: b.korean ? info.controlsKO : info.controlsEN)
    }

    static func gameCode(_ id: String) -> String? {
        switch id {
        case "snake": return GamesOne.snake
        case "breakout": return GamesOne.breakout
        case "pong": return GamesOne.pong
        case "hopper": return GamesOne.hopper
        case "shooter": return GamesTwo.shooter
        case "runner": return GamesTwo.runner
        case "dodge": return GamesTwo.dodge
        case "platformer": return GamesTwo.platformer
        default: return nil
        }
    }

    static func defaultTitle(_ info: TemplateInfo, _ b: ProgramBrief) -> String {
        if let subject = b.subject, info.kind == "website" { return subject.prefix(1).uppercased() + subject.dropFirst() }
        return b.korean ? info.nameKO : info.nameEN
    }

    // MARK: Configuration

    static let hex: [String: String] = [
        "red": "#ef4444", "orange": "#f97316", "yellow": "#facc15", "lime": "#84cc16", "green": "#22c55e", "darkgreen": "#15803d",
        "teal": "#14b8a6", "cyan": "#22d3ee", "blue": "#3b82f6", "navy": "#1e3a8a", "purple": "#a855f7", "pink": "#ec4899",
        "maroon": "#7f1d1d", "white": "#f8fafc", "beige": "#f5e6c8", "brown": "#92400e", "black": "#111827", "gray": "#9ca3af",
        "darkgray": "#374151", "silver": "#cbd5e1", "gold": "#fbbf24",
    ]

    static func theme(_ b: ProgramBrief) -> String {
        for (style, theme) in [("neon", "neon"), ("retro", "retro"), ("pixel", "retro"), ("pastel", "pastel"), ("cute", "pastel"), ("light", "light")] where b.styles.contains(style) {
            return theme
        }
        return "dark"
    }

    /// config.js: everything the request decided, read by the template at run time.
    static func config(_ b: ProgramBrief, info: TemplateInfo, title: String) -> String {
        var pairs: [DataPair] = []
        func put(_ k: String, _ v: DataValue) { pairs.append(DataPair(key: k, value: v)) }
        let slug = String(title.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.prefix(24).map(Character.init))
        put("id", .string(info.id + "-" + (slug.isEmpty ? "app" : slug)))
        put("title", .string(title))
        put("lang", .string(b.korean ? "ko" : "en"))
        put("theme", .string(theme(b)))
        put("pixel", .bool(b.styles.contains("pixel") || b.styles.contains("retro")))
        put("glow", .bool(b.styles.contains("neon") || b.styles.contains("futuristic")))
        let speed = b.numbers["speed"] ?? 1
        put("speed", .double((speed * 100).rounded() / 100))
        put("difficulty", .int(Int(b.numbers["difficulty"] ?? 1)))
        for key in ["lives", "levels", "time", "grid", "target", "items", "win", "players"] {
            if let v = b.numbers[key] ?? info.defaults[key] { put(key, .int(Int(v))) }
        }
        if b.request.lowercased().contains("wrap") || b.request.lowercased().contains("no walls") || b.request.contains("벽 없") { put("wrap", .bool(true)) }
        var colors: [DataPair] = []
        for (role, key) in b.colors.sorted(by: { $0.key < $1.key }) {
            guard let h = hex[key] else { continue }
            // "a red snake game": the main colour goes to the main thing of the template.
            let mapped = role == "main" ? mainRole(info.id) : role
            colors.append(DataPair(key: mapped, value: .string(h)))
            if role == "main" { colors.append(DataPair(key: "accent", value: .string(h))) }
        }
        put("colors", .object(colors))
        var features: [DataPair] = []
        let defaultsOn: [String] = ["sound", "highscore", "pause", "particles", "levels"]
        for f in defaultsOn where !b.excluded.contains(f) { features.append(DataPair(key: f, value: .bool(true))) }
        for f in b.features where !defaultsOn.contains(f) { features.append(DataPair(key: f, value: .bool(true))) }
        for f in b.excluded { features.append(DataPair(key: f, value: .bool(false))) }
        put("features", .object(features))
        put("strings", .object(strings(info, b).map { DataPair(key: $0.0, value: .string($0.1)) }))
        return "/* Settings from your request — edit freely, the game reads them at start. */\nwindow.CONFIG = " + JSONWriter.write(.object(pairs)).trimmingCharacters(in: .newlines) + ";\n"
    }

    static func mainRole(_ template: String) -> String {
        switch template {
        case "snake": return "snake"
        case "breakout", "pong": return "paddle"
        case "hopper", "shooter", "runner", "dodge", "platformer": return "player"
        case "blocks": return "blocks"
        case "memory": return "cards"
        default: return "accent"
        }
    }

    static func strings(_ info: TemplateInfo, _ b: ProgramBrief) -> [(String, String)] {
        if !b.korean {
            return [("controls", info.controlsEN)]
        }
        var s: [(String, String)] = [
            ("start", "시작"), ("again", "다시 하기"), ("gameOver", "게임 오버"), ("score", "점수"), ("best", "최고"), ("newRecord", "신기록!"),
            ("paused", "일시정지"), ("pausedHint", "P를 누르거나 탭하면 계속합니다"), ("resume", "계속"), ("youWin", "승리!"), ("level", "레벨"),
            ("lives", "목숨"), ("time", "시간"), ("timeUp", "시간 종료"), ("launch", "탭하거나 스페이스를 눌러 발사"), ("firstTo", "목표 점수"),
            ("twoPlayers", "2인용"), ("vsComputer", "컴퓨터와 대결"), ("leftWins", "왼쪽 플레이어 승리"), ("rightWins", "오른쪽 플레이어 승리"),
            ("controls", info.controlsKO), ("wave", "웨이브"), ("survived", "버텼습니다!"),
        ]
        let intros: [String: String] = [
            "snake": "방향키나 스와이프로 조종하세요.\n먹이를 먹고 자라세요 — 벽과 꼬리는 피하세요.",
            "breakout": "← → 또는 드래그로 움직이고, 스페이스나 탭으로 공을 발사하세요.\n벽돌을 모두 깨세요!",
            "pong": "↑ ↓ 또는 드래그로 패들을 움직이세요. 컴퓨터를 이기세요!",
            "hopper": "탭, 클릭 또는 스페이스로 날갯짓하세요.\n틈 사이로 날아가세요!",
            "shooter": "← → 또는 드래그로 움직이고, 스페이스를 누르거나 화면을 눌러 발사하세요.\n모든 웨이브를 물리치세요!",
            "runner": "스페이스, ↑ 또는 탭으로 점프하고 ↓ 로 숙이세요.\n최대한 멀리 달리세요!",
            "dodge": "← → 또는 드래그로 움직이세요.\n빨간 것은 피하고 별은 잡으세요!",
            "platformer": "← → 로 달리고 스페이스 / ↑ 로 점프하세요 (길게 누르면 더 높이).\n적을 밟고, 동전을 모으고, 깃발까지 가세요!",
        ]
        if let intro = intros[info.id] { s.append(("intro", intro)) }
        if info.id == "pong" { s.append(("intro2", "왼쪽: W / S · 오른쪽: ↑ / ↓ (각 절반을 드래그해도 됩니다)")) }
        return s
    }

    static func readme(_ info: TemplateInfo, _ b: ProgramBrief, title: String, handled: [String], unhandled: [String]) -> String {
        let ko = b.korean
        var lines = ["# \(title)", "", ko ? "Jarvis가 만든 \(info.nameKO) \(info.kind == "game" ? "게임" : "앱")입니다." : "A \(info.nameEN) \(info.kind) made by Jarvis.", ""]
        lines.append(ko ? "## 조작" : "## Controls")
        lines.append(ko ? info.controlsKO : info.controlsEN)
        lines.append("")
        lines.append(ko ? "## 요청에서 반영한 것" : "## From your request")
        if handled.isEmpty { lines.append(ko ? "- 기본 구성" : "- the standard version") }
        for f in handled { lines.append("- \(f)") }
        for (role, color) in b.colors.sorted(by: { $0.key < $1.key }) { lines.append("- \(role): \(color)") }
        if let s = b.numbers["speed"], s != 1 { lines.append("- speed ×\(s)") }
        if !unhandled.isEmpty {
            lines.append("")
            lines.append(ko ? "## 아직 없는 것" : "## Not included yet")
            for f in unhandled { lines.append("- \(f)") }
        }
        lines.append("")
        lines.append(ko ? "## 파일" : "## Files")
        lines.append(ko ? "- index.html — 열면 바로 실행됩니다 (인터넷 불필요)\n- config.js — 색, 속도, 목숨 같은 설정\n- game.js — 게임 규칙\n- kit.js — 화면, 입력, 소리, 저장\n- style.css — 모양"
                     : "- index.html — open it to play (works offline)\n- config.js — colours, speed, lives and other settings\n- game.js — the game rules\n- kit.js — screen, input, sound, saving\n- style.css — the look")
        return lines.joined(separator: "\n") + "\n"
    }
}
