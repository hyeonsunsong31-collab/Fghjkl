import Foundation

/// Gathers the candidate context channels the thalamus chooses from.
@MainActor
enum ContextBuilder {
    static func channels(for c: JarvisController, language: DetectedLanguage) -> [ContextChannel] {
        var out: [ContextChannel] = []
        let encoder = c.brain.encoder

        // Recent conversation (most recent first gets highest recency).
        let recent = c.messages.filter { $0.role != .system && !$0.text.isEmpty }.suffix(8)
        for (i, m) in recent.enumerated() {
            let recency = Float(i + 1) / Float(max(1, recent.count))
            let speaker = m.role == .user ? (language == .korean ? "사용자" : "User") : "Jarvis"
            out.append(ContextChannel(id: "msg-\(m.id)", kind: .conversation, text: "\(speaker): \(m.text.prefix(400))",
                                      salience: 0.5, recency: recency, encoder: encoder))
        }

        // 3D workspace.
        if c.spaceOpen || !c.scene.document.objects.isEmpty {
            out.append(ContextChannel(id: "scene", kind: .scene, text: c.scene.document.summary(),
                                      salience: c.spaceOpen ? 0.7 : 0.3, recency: c.spaceOpen ? 0.9 : 0.3, encoder: encoder))
        }

        // Device state and time.
        let body = DeviceState.body()
        let f = DateFormatter()
        f.locale = Locale(identifier: language == .korean ? "ko_KR" : "en_GB")
        f.dateStyle = .full
        f.timeStyle = .short
        out.append(ContextChannel(id: "device", kind: .device,
                                  text: "Now: \(f.string(from: Date())). Device: \(DeviceState.deviceName), battery \(Int(body.batteryLevel * 100))%\(body.isCharging ? " (charging)" : "").",
                                  salience: 0.35, recency: 1, encoder: encoder))

        // Running workflow.
        if let wf = c.currentWorkflow ?? c.interruptedWorkflow {
            out.append(ContextChannel(id: "task", kind: .task, text: "Task “\(wf.title)”: \(wf.narration(language))",
                                      salience: 0.6, recency: 0.8, encoder: encoder))
        }

        // What is on screen.
        if c.activePanel == .browser, let url = c.web.currentURL {
            out.append(ContextChannel(id: "screen", kind: .screen, text: "Browser shows: \(c.web.title) (\(url.absoluteString))",
                                      salience: 0.5, recency: 0.9, encoder: encoder))
        }
        if let song = c.music.nowPlaying {
            out.append(ContextChannel(id: "music", kind: .screen, text: "Now playing: \(song)", salience: 0.3, recency: 0.7, encoder: encoder))
        }

        // Results of the last turn's tools.
        for (i, call) in ToolCallLog.shared.calls.suffix(3).enumerated() {
            out.append(ContextChannel(id: "tool-\(i)", kind: .toolResult, text: "\(call.name) → \(call.result.prefix(300))",
                                      salience: 0.5, recency: 0.6, encoder: encoder))
        }

        // User profile.
        out.append(ContextChannel(id: "profile", kind: .profile,
                                  text: language == .korean ? "사용자는 한국어와 영어를 모두 사용합니다. 응답은 사용자의 언어로 합니다." : "The user speaks Korean and English; reply in the user's language.",
                                  salience: 0.3, recency: 0.5, encoder: encoder))
        return out
    }
}
