import Foundation
import UIKit

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
            c.setSpaceOpen(true)
            let description = p["description"] ?? "sculpture"
            var spec = ModelSpec.template(for: description)
            let isGeneric = spec.name.lowercased() == description.lowercased().capitalized.lowercased() || spec.name == "Sculpture"
            if c.appleFM.isAvailable && isGeneric {
                if let designed = try? await AppleFMDesigner.design(description, language: language), designed.parts.count >= 2 {
                    spec = designed
                }
            }
            c.scene.createComposite(spec, color: p["color"])
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
            let (ok, detail) = await AppCatalog.open(p["app"] ?? "")
            return CommandOutcome(success: ok, detail: ok ? "" : detail)
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
            return CommandOutcome(success: ok, detail: ok ? "" : detail)
        case .message:
            let (ok, detail) = await c.personal.message(p["contact"], body: p["body"])
            return CommandOutcome(success: ok, detail: ok ? "" : detail)
        }
    }

    private func noTarget(_ ko: Bool) -> String {
        ko ? "대상 오브젝트를 찾지 못했습니다. 먼저 오브젝트를 만들거나 선택해 주십시오." : "I couldn't find that object; please create or select one first."
    }
}
