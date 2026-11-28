import Foundation

/// While the studio is open, which sentences are work for its queue ("make the snake faster",
/// "3 lives", "배경을 검게 바꿔") and which keep their usual meaning (music, timers, apps, questions).
enum StudioRouting {
    /// Commands that keep their usual meaning while the studio is open.
    static let assistantIntents: Set<CommandIntent> = [
        .wake, .sleep, .stopSpeaking, .muteMic, .unmuteMic, .muteVoice, .unmuteVoice, .help, .showHistory, .showBrain, .openSettings,
        .resumeTask, .cancelTask, .deepThinkOn, .deepThinkOff, .setVoice, .speakFaster, .speakSlower, .setLanguage, .open3D, .close3D,
        .playMusic, .pauseMusic, .resumeMusic, .stopMusic, .nextTrack, .openBrowser, .webSearch, .openURL, .openApp, .flashlightOn,
        .flashlightOff, .setBrightness, .setVolume, .batteryStatus, .timeQuery, .dateQuery, .setTimer, .setAlarm, .runShortcut,
        .systemSetting, .call, .message, .openStudio, .handTrackingOn, .handTrackingOff,
    ]

    /// Words of an edit or a build request.
    static let editWords = ["make", "add", "change", "remove", "delete", "set", "increase", "decrease", "faster", "slower", "bigger",
                            "smaller", "harder", "easier", "more", "fewer", "less", "color", "colour", "rename", "replace", "put",
                            "turn", "fix", "improve", "redesign", "upgrade", "translate", "convert", "build", "create",
                            "바꿔", "변경", "추가", "넣어", "빼", "없애", "제거", "빠르게", "느리게", "크게", "작게", "어렵게", "쉽게", "더 ",
                            "색", "고쳐", "수정", "개선", "업그레이드", "번역", "변환", "만들어", "늘려", "줄여"]

    static func isStudioWork(_ text: String, parsed: GrammarResult) -> Bool {
        if let first = parsed.commands.first, assistantIntents.contains(first.intent), first.confidence >= 0.75 { return false }
        // Anything that names a feature, colour, number or style of a product is an edit of it.
        let brief = ProgramBrief.parse(text)
        if !brief.features.isEmpty || !brief.colors.isEmpty || !brief.numbers.isEmpty || !brief.excluded.isEmpty || !brief.styles.isEmpty {
            return true
        }
        let lower = text.lowercased()
        return editWords.contains { lower.contains($0) }
    }
}
