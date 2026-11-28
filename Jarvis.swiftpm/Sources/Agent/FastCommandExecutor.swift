import Foundation
import UIKit
import os

/// Result of executing one built-in command.
struct CommandOutcome {
    var success: Bool
    /// Extra information for the reply (e.g. the battery level), or the failure cause.
    var detail: String = ""
    var artifacts: [URL] = []
    /// Replace the persona confirmation with this text.
    var spokenOverride: String?
}

/// Executes grammar commands directly (no language model) — the instant path.
@MainActor
final class FastCommandExecutor {
    unowned let c: JarvisController

    init(controller: JarvisController) { c = controller }

    func execute(_ command: Command, language: DetectedLanguage, runID: String?) async -> CommandOutcome {
        let p = command.parameters
        let ko = language == .korean
        switch command.intent {
        // MARK: Assistant
        case .wake:
            c.wake(source: .text, speak: false)
            return CommandOutcome(success: true)
        case .sleep:
            c.sleep()
            return CommandOutcome(success: true)
        case .stopSpeaking:
            c.speech.stop()
            // "Stop" / "그만" while a song plays and Jarvis was not talking means the music.
            let bargeIn: Bool = Date().timeIntervalSince(c.lastSpeechInterruption) < 2
            if !bargeIn && c.music.isPlaying { _ = await c.music.pause() }
            return CommandOutcome(success: true)
        case .muteMic:
            c.setMicMuted(true)
            return CommandOutcome(success: true)
        case .unmuteMic:
            c.setMicMuted(false)
            return CommandOutcome(success: true)
        case .muteVoice:
            c.setVoiceMuted(true)
            return CommandOutcome(success: true)
        case .unmuteVoice:
            c.setVoiceMuted(false)
            return CommandOutcome(success: true)
        case .help:
            c.showPanel(.help)
            return CommandOutcome(success: true)
        case .showHistory:
            c.showPanel(.history)
            return CommandOutcome(success: true)
        case .showBrain:
            c.showPanel(.brain)
            return CommandOutcome(success: true)
        case .openSettings:
            c.showPanel(.settings)
            return CommandOutcome(success: true)
        case .resumeTask:
            let resumed = await c.resumeInterruptedWorkflow()
            return CommandOutcome(success: resumed, detail: resumed ? "" : (ko ? "재개할 작업이 없습니다." : "There is no interrupted task to resume."))
        case .cancelTask:
            c.cancelCurrentTurn()
            c.pendingConfirmation = nil
            return CommandOutcome(success: true)
        case .deepThinkOn:
            guard c.deepThink.isAvailable else {
                c.showPanel(.settings)
                return CommandOutcome(success: false, detail: ko ? "심층 사고 모델이 아직 설치되지 않았습니다. 설정에서 내려받아 주십시오." : "The Deep-Think model isn't installed yet; you can download it in Settings.")
            }
            c.deepThinkEnabled = true
            return CommandOutcome(success: true)
        case .deepThinkOff:
            c.deepThinkEnabled = false
            return CommandOutcome(success: true)
        case .setVoice:
            if let v = p["voice"] { c.setEnglishVoice("bm_" + v) }
            return CommandOutcome(success: true)
        case .speakFaster:
            c.adjustSpeechRate(faster: true)
            return CommandOutcome(success: true)
        case .speakSlower:
            c.adjustSpeechRate(faster: false)
            return CommandOutcome(success: true)
        case .setLanguage:
            switch p["language"] {
            case "ko": c.setLanguageMode(.korean)
            case "en": c.setLanguageMode(.english)
            default: c.setLanguageMode(.auto)
            }
            return CommandOutcome(success: true)

        // MARK: 3D space
        case .open3D:
            c.setSpaceOpen(true)
            return CommandOutcome(success: true)
        case .close3D:
            c.setSpaceOpen(false)
            return CommandOutcome(success: true)
        case .handTrackingOn:
            c.setSpaceOpen(true)
            await c.setHandTracking(true)
            let ok = c.hands.isRunning
            return CommandOutcome(success: ok, detail: ok ? "" : c.hands.status)
        case .handTrackingOff:
            await c.setHandTracking(false)
            return CommandOutcome(success: true)
        case .createObject:
            c.setSpaceOpen(true)
            let shape = p["shape"] ?? "cube"
            let count = Int(p["count"] ?? "1") ?? 1
            let size = Float(p["size"] ?? "1") ?? 1
            let made = c.scene.create(shape: shape, color: p["color"], count: count, sizeFactor: size, text: p["content"])
            return CommandOutcome(success: !made.isEmpty)
        case .generateModel:
            return await design(p["request"] ?? p["description"] ?? "sculpture", description: p["description"], language: language)
        case .refineModel:
            return await refine(p["request"] ?? command.text, language: language)
        case .setRenderStyle:
            c.setSpaceOpen(true)
            c.scene.setRenderStyle(p["style"] == "hologram" ? .hologram : .solid)
            return CommandOutcome(success: true)
        case .cloneObject:
            let made = c.scene.clone(p, count: Int(p["count"] ?? "1") ?? 1)
            return made.isEmpty ? CommandOutcome(success: false, detail: noTarget(ko)) : CommandOutcome(success: true)
        case .deleteObject:
            let n = c.scene.delete(p)
            return n > 0 ? CommandOutcome(success: true) : CommandOutcome(success: false, detail: noTarget(ko))
        case .clearScene:
            c.scene.clear()
            return CommandOutcome(success: true)
        case .selectObject:
            return c.scene.select(p) ? CommandOutcome(success: true) : CommandOutcome(success: false, detail: noTarget(ko))
        case .moveObject:
            let ok = c.scene.move(p, direction: p["direction"] ?? "right", amount: Float(p["amount"] ?? "0.2") ?? 0.2)
            return ok ? CommandOutcome(success: true) : CommandOutcome(success: false, detail: noTarget(ko))
        case .scaleObject:
            let ok = c.scene.scale(p, factor: Float(p["factor"] ?? "1.5") ?? 1.5)
            return ok ? CommandOutcome(success: true) : CommandOutcome(success: false, detail: noTarget(ko))
        case .rotateObject:
            let ok = c.scene.rotate(p, degrees: Float(p["degrees"] ?? "45") ?? 45, axis: p["axis"] ?? "y")
            return ok ? CommandOutcome(success: true) : CommandOutcome(success: false, detail: noTarget(ko))
        case .colorObject:
            let ok = c.scene.recolor(p, color: p["color"] ?? "cyan")
            return ok ? CommandOutcome(success: true) : CommandOutcome(success: false, detail: noTarget(ko))
        case .undo:
            return c.scene.undo() ? CommandOutcome(success: true) : CommandOutcome(success: false, detail: ko ? "되돌릴 작업이 없습니다." : "There is nothing to undo.")
        case .redo:
            return c.scene.redo() ? CommandOutcome(success: true) : CommandOutcome(success: false, detail: ko ? "다시 실행할 작업이 없습니다." : "There is nothing to redo.")
        case .exportModel:
            guard !c.scene.document.objects.isEmpty else {
                return CommandOutcome(success: false, detail: ko ? "내보낼 오브젝트가 없습니다." : "The workspace is empty; there is nothing to export.")
            }
            let files = c.scene.export()
            for f in files { RecordKeeper.shared.registerArtifact(at: f, runID: runID, description: "3D model export (\(f.pathExtension))") }
            return CommandOutcome(success: !files.isEmpty, detail: files.map(\.lastPathComponent).joined(separator: ", "), artifacts: files)
        case .saveWallpaper:
            c.setSpaceOpen(true)
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let image = await c.scene.snapshot() else {
                return CommandOutcome(success: false, detail: ko ? "3D 공간을 캡처하지 못했습니다." : "I couldn't capture the workspace.")
            }
            do {
                let url = try await WallpaperService.save(image, runID: runID)
                return CommandOutcome(success: true, artifacts: url.map { [$0] } ?? [])
            } catch {
                return CommandOutcome(success: false, detail: error.localizedDescription)
            }
        case .resetCamera:
            c.scene.resetCamera()
            return CommandOutcome(success: true)

        // MARK: Music & web
        case .playMusic:
            let q = p["query"]
            let lower = (q ?? "").lowercased()
            let fromLibrary = lower.contains("my library") || lower.contains("보관함")
            let (ok, detail) = fromLibrary
                ? await c.music.playFromLibrary(q?.replacingOccurrences(of: "my library", with: "").replacingOccurrences(of: "보관함", with: "") ?? "")
                : await c.music.play(query: q)
            return CommandOutcome(success: ok, detail: ok ? "" : detail)
        case .pauseMusic:
            _ = await c.music.pause()
            return CommandOutcome(success: true)
        case .resumeMusic:
            let (ok, detail) = await c.music.resume()
            return CommandOutcome(success: ok, detail: ok ? "" : detail)
        case .stopMusic:
            _ = await c.music.stop()
            return CommandOutcome(success: true)
        case .nextTrack:
            let (ok, detail) = await c.music.next()
            return CommandOutcome(success: ok, detail: ok ? "" : detail)
        case .openStudio:
            c.showPanel(.studio)
            return CommandOutcome(success: true)
        case .buildProgram:
            c.showPanel(.studio)
            StudioController.shared.request(p["request"] ?? command.text, korean: ko)
            return CommandOutcome(success: true)
        case .openBrowser:
            c.showPanel(.browser)
            if c.web.currentURL == nil, let home = URL(string: "https://duckduckgo.com") { await c.web.load(home) }
            return CommandOutcome(success: true)
        case .webSearch:
            c.showPanel(.browser)
            let results = await c.web.search(p["query"] ?? "")
            if results.isEmpty { return CommandOutcome(success: false, detail: ko ? "검색 결과를 가져오지 못했습니다. 인터넷 연결을 확인해 주십시오." : "I couldn't fetch results; please check the internet connection.") }
            let top = results.prefix(3).map(\.title).joined(separator: ko ? ", " : "; ")
            return CommandOutcome(success: true, detail: top,
                                  spokenOverride: ko ? "검색 결과 상위 항목은 \(top)입니다." : "The top results are: \(top), sir.")
        case .openURL:
            c.showPanel(.browser)
            if let s = p["url"], let url = URL(string: s) { await c.web.load(url) }
            return CommandOutcome(success: true)

        // MARK: Device
        case .openApp:
            switch await AppCatalog.open(p["app"] ?? "", korean: ko) {
            case .opened(let name):
                return CommandOutcome(success: true, detail: name)
            case .web(let name, let site):
                c.offerLink(URLOpener.lastRefused, title: ko ? "\(name) 앱 열기" : "Open the \(name) app")
                c.showPanel(.browser)
                await c.web.load(site)
                return CommandOutcome(success: true, detail: name,
                                      spokenOverride: ko ? "iOS가 \(name) 앱 열기를 허용하지 않아, 제 브라우저에서 \(name) 웹사이트를 열었습니다."
                                                         : "iOS wouldn't let me open the \(name) app, so I've opened \(name) on the web in my browser, sir.")
            case .failed(let message):
                c.offerLink(URLOpener.lastRefused, title: ko ? "탭하여 열기" : "Tap to open")
                return CommandOutcome(success: false, detail: message)
            }
        case .flashlightOn, .flashlightOff:
            let (ok, detail) = DeviceControls.setTorch(command.intent == .flashlightOn)
            return CommandOutcome(success: ok, detail: detail)
        case .setBrightness:
            let value = DeviceControls.setBrightness(level: Double(p["level"] ?? ""), delta: Double(p["delta"] ?? ""))
            return CommandOutcome(success: true, detail: "\(Int(value * 100))%")
        case .setVolume:
            let value = DeviceControls.setVolume(level: Double(p["level"] ?? ""), delta: Double(p["delta"] ?? ""))
            return CommandOutcome(success: true, detail: "\(Int(value * 100))%")
        case .batteryStatus:
            let d = DeviceControls.batteryDescription(language)
            return CommandOutcome(success: true, detail: d, spokenOverride: d)
        case .timeQuery:
            let d = DeviceControls.timeDescription(language)
            return CommandOutcome(success: true, detail: d, spokenOverride: d)
        case .dateQuery:
            let d = DeviceControls.dateDescription(language)
            return CommandOutcome(success: true, detail: d, spokenOverride: d)
        case .setTimer:
            guard let s = Int(p["seconds"] ?? ""), s > 0 else {
                return CommandOutcome(success: false, detail: ko ? "몇 분으로 맞출지 말씀해 주십시오." : "How long should the timer run, sir?")
            }
            let ok = await DeviceControls.scheduleTimer(seconds: s, language: language)
            return CommandOutcome(success: ok, detail: ok ? "" : (ko ? "알림 권한이 필요합니다." : "Notification permission is required."))
        case .setAlarm:
            guard let h = Int(p["hour"] ?? ""), let m = Int(p["minute"] ?? "0") else {
                return CommandOutcome(success: false, detail: ko ? "몇 시로 맞출지 말씀해 주십시오." : "For what time, sir?")
            }
            let ok = await DeviceControls.scheduleAlarm(hour: h, minute: m, language: language)
            return CommandOutcome(success: ok, detail: ok ? "" : (ko ? "알림 권한이 필요합니다." : "Notification permission is required."))
        case .runShortcut:
            let ok = await ShortcutsBridge.run(p["name"] ?? "")
            return CommandOutcome(success: ok, detail: ok ? "" : (ko ? "단축어 앱을 열 수 없습니다." : "The Shortcuts app could not be opened."))
        case .systemSetting:
            let ok = await ShortcutsBridge.setSystemSetting(p["setting"] ?? "", value: p["value"] ?? "toggle")
            return CommandOutcome(success: ok, detail: ok ? "" : (ko ? "'Jarvis Bridge' 단축어가 필요합니다. 설정의 안내를 참고해 주십시오." : "This needs the 'Jarvis Bridge' shortcut; see the guide in Settings."))
        case .call:
            let (ok, detail) = await c.personal.call(p["contact"] ?? "")
            if !ok { c.offerLink(URLOpener.lastRefused, title: ko ? "탭하여 전화 걸기" : "Tap to call") }
            return CommandOutcome(success: ok, detail: ok ? "" : detail)
        case .message:
            let (ok, detail) = await c.personal.message(p["contact"], body: p["body"])
            if !ok { c.offerLink(URLOpener.lastRefused, title: ko ? "탭하여 메시지 열기" : "Tap to open Messages") }
            return CommandOutcome(success: ok, detail: ok ? "" : detail)
        }
    }

    // MARK: Design (detailed 3D modelling)

    /// Apple Intelligence designs whatever the parametric library cannot (when available).
    private var designer: DesignStudio.Designer? {
        guard AppleFMDesigner.isAvailable else { return nil }
        return { prompt in await AppleFMDesigner.design(prompt) }
    }

    private func design(_ request: String, description: String?, language: DetectedLanguage) async -> CommandOutcome {
        c.setSpaceOpen(true)
        var brief = DesignBrief.parse(request, description: description)
        brief.korean = language == .korean
        let outcome = await DesignStudio.design(brief, designer: designer)
        c.scene.createComposite(outcome.spec, design: Self.encode(brief))
        Self.log("Design", outcome)
        return CommandOutcome(success: true, detail: "\(outcome.spec.parts.count) parts", spokenOverride: DesignReport.text(outcome))
    }

    /// "make the wheels gold", "add a chimney", "remove the spoiler", "two more legs" → the same model, revised.
    private func refine(_ request: String, language: DetectedLanguage) async -> CommandOutcome {
        guard let target = c.scene.designTarget(), let base = target.design.flatMap(Self.decode) else {
            // Nothing has been designed yet: treat it as a new design request.
            return await design(request, description: nil, language: language)
        }
        c.setSpaceOpen(true)
        var edit = DesignBrief.parse(request)
        edit.korean = language == .korean
        let lower = request.lowercased()
        let more = ["more", "extra", "another", "하나 더", "더 달", "더 추가", "추가"].contains { lower.contains($0) }
        let fewer = ["fewer", "less ", "덜", "줄여"].contains { lower.contains($0) }
        if more || fewer {
            // Relative counts ("two more legs") start from what the model has now.
            let used = DesignLibrary.design(base)?.counts ?? [:]
            for (component, n) in edit.counts {
                let have = used[component] ?? base.counts[component] ?? 0
                edit.counts[component] = Swift.max(0, fewer ? have - n : have + n)
            }
        }
        let refined = base.refined(by: edit)
        let outcome = await DesignStudio.design(refined, designer: designer)
        c.scene.refineDesign(target.id, spec: outcome.spec, design: Self.encode(refined))
        Self.log("Refined design", outcome)
        return CommandOutcome(success: true, detail: "\(outcome.spec.parts.count) parts", spokenOverride: DesignReport.changes(edit, outcome: outcome))
    }

    private static func encode(_ brief: DesignBrief) -> String? {
        (try? JSONEncoder().encode(brief)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func decode(_ json: String) -> DesignBrief? {
        json.data(using: .utf8).flatMap { try? JSONDecoder().decode(DesignBrief.self, from: $0) }
    }

    /// Diagnostics only (no user words): what was designed and how faithfully.
    private static func log(_ label: String, _ o: DesignStudio.Outcome) {
        let subject: String = o.brief.subject.map { s in o.brief.variant.map { "\(s)/\($0)" } ?? s } ?? "unknown"
        let source: String = o.source.rawValue
        let parts: Int = o.spec.parts.count
        let colours: String = o.brief.colors.keys.sorted().joined(separator: ",")
        let counts: String = o.brief.counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        let missing: String = o.unhandled.joined(separator: ",")
        Log.space.info("\(label, privacy: .public): \(subject, privacy: .public) via \(source, privacy: .public) parts=\(parts, privacy: .public) colours=[\(colours, privacy: .public)] counts=[\(counts, privacy: .public)] missing=[\(missing, privacy: .public)]")
    }

    private func noTarget(_ ko: Bool) -> String {
        ko ? "대상 오브젝트를 찾지 못했습니다. 먼저 오브젝트를 만들거나 선택해 주십시오." : "I couldn't find that object; please create or select one first."
    }
}
