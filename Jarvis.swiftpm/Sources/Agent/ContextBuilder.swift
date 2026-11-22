import Foundation

/// Gathers the candidate context channels the thalamus chooses from.
/// (Split into small helpers so the Swift compiler in Swift Playground type-checks it quickly.)
@MainActor
enum ContextBuilder {
    static func channels(for c: JarvisController, language: DetectedLanguage) -> [ContextChannel] {
        let encoder: TextEncoder = c.brain.encoder
        var out: [ContextChannel] = conversation(c, language: language, encoder: encoder)
        if let scene = sceneChannel(c, encoder: encoder) { out.append(scene) }
        out.append(deviceChannel(language: language, encoder: encoder))
        if let task = taskChannel(c, language: language, encoder: encoder) { out.append(task) }
        out.append(contentsOf: screenChannels(c, encoder: encoder))
        out.append(contentsOf: toolChannels(encoder: encoder))
        out.append(profileChannel(language: language, encoder: encoder))
        return out
    }

    /// Recent conversation (most recent first gets highest recency).
    private static func conversation(_ c: JarvisController, language: DetectedLanguage, encoder: TextEncoder) -> [ContextChannel] {
        let recent: [ChatMessage] = Array(c.messages.filter { $0.role != .system && !$0.text.isEmpty }.suffix(8))
        var out: [ContextChannel] = []
        let userName: String = language == .korean ? "사용자" : "User"
        for (i, m) in recent.enumerated() {
            let recency: Float = Float(i + 1) / Float(max(1, recent.count))
            let speaker: String = m.role == .user ? userName : "Jarvis"
            let text: String = speaker + ": " + String(m.text.prefix(400))
            out.append(ContextChannel(id: "msg-\(m.id)", kind: .conversation, text: text,
                                      salience: 0.5, recency: recency, encoder: encoder))
        }
        return out
    }

    /// The 3D workspace.
    private static func sceneChannel(_ c: JarvisController, encoder: TextEncoder) -> ContextChannel? {
        let open: Bool = c.spaceOpen
        guard open || !c.scene.document.objects.isEmpty else { return nil }
        return ContextChannel(id: "scene", kind: .scene, text: c.scene.document.summary(),
                              salience: open ? 0.7 : 0.3, recency: open ? 0.9 : 0.3, encoder: encoder)
    }

    /// Device state and time.
    private static func deviceChannel(language: DetectedLanguage, encoder: TextEncoder) -> ContextChannel {
        let body = DeviceState.body()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .korean ? "ko_KR" : "en_GB")
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        let battery: Int = Int(body.batteryLevel * 100)
        let charging: String = body.isCharging ? " (charging)" : ""
        let now: String = formatter.string(from: Date())
        let text: String = "Now: \(now). Device: \(DeviceState.deviceName), battery \(battery)%\(charging)."
        return ContextChannel(id: "device", kind: .device, text: text, salience: 0.35, recency: 1, encoder: encoder)
    }

    /// The running (or interrupted) workflow.
    private static func taskChannel(_ c: JarvisController, language: DetectedLanguage, encoder: TextEncoder) -> ContextChannel? {
        guard let wf = c.currentWorkflow ?? c.interruptedWorkflow else { return nil }
        let text: String = "Task \u{201C}\(wf.title)\u{201D}: " + wf.narration(language)
        return ContextChannel(id: "task", kind: .task, text: text, salience: 0.6, recency: 0.8, encoder: encoder)
    }

    /// What is on screen: the agent browser and the music player.
    private static func screenChannels(_ c: JarvisController, encoder: TextEncoder) -> [ContextChannel] {
        var out: [ContextChannel] = []
        if c.activePanel == .browser, let url = c.web.currentURL {
            let text: String = "Browser shows: \(c.web.title) (\(url.absoluteString))"
            out.append(ContextChannel(id: "screen", kind: .screen, text: text, salience: 0.5, recency: 0.9, encoder: encoder))
        }
        if let song = c.music.nowPlaying {
            out.append(ContextChannel(id: "music", kind: .screen, text: "Now playing: \(song)", salience: 0.3, recency: 0.7, encoder: encoder))
        }
        return out
    }

    /// Results of the last turn's tools.
    private static func toolChannels(encoder: TextEncoder) -> [ContextChannel] {
        var out: [ContextChannel] = []
        let calls: [ToolCallRecord] = Array(ToolCallLog.shared.calls.suffix(3))
        for (i, call) in calls.enumerated() {
            let text: String = call.name + " \u{2192} " + String(call.result.prefix(300))
            out.append(ContextChannel(id: "tool-\(i)", kind: .toolResult, text: text, salience: 0.5, recency: 0.6, encoder: encoder))
        }
        return out
    }

    /// The user profile.
    private static func profileChannel(language: DetectedLanguage, encoder: TextEncoder) -> ContextChannel {
        let text: String = language == .korean
            ? "사용자는 한국어와 영어를 모두 사용합니다. 응답은 사용자의 언어로 합니다."
            : "The user speaks Korean and English; reply in the user's language."
        return ContextChannel(id: "profile", kind: .profile, text: text, salience: 0.3, recency: 0.5, encoder: encoder)
    }
}
