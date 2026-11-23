import Foundation
import NaturalLanguage
import SwiftUI
import UIKit
import Observation
import os

enum AssistantPhase: String {
    case asleep, listening, thinking, speaking
}

enum Panel: String, Identifiable {
    case history, brain, settings, browser, help, onboarding
    var id: String { rawValue }
}

struct ChatMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant, system }
    var id = UUID()
    var role: Role
    var text: String
    var language: DetectedLanguage
    var timestamp = Date()
    var isStreaming = false
}

/// The central state of Jarvis: owns every service and exposes the UI state.
@MainActor
@Observable
final class JarvisController {
    static let shared = JarvisController()

    // MARK: UI state
    var phase: AssistantPhase = .asleep
    var isAwake: Bool { phase != .asleep }
    var micMuted = false
    var voiceMuted = false
    var handTrackingEnabled = false
    var spaceOpen = false
    var activePanel: Panel?
    var messages: [ChatMessage] = []
    var partialTranscript = ""
    var inputLevel: Float = 0
    var lastTurn: AgentTurnResult?
    var currentWorkflow: Workflow?
    var deepThinkEnabled = false
    var languageMode: LanguageMode = .auto
    var currentLanguage: DetectedLanguage = .english
    var pendingConfirmation: Command?
    var statusNote = ""
    var latticeSample: [NeuronID] = []
    var latticeStats: LatticeTickStats?
    var kokoroStatus = "—"
    var kokoroProgress: Double?
    var interruptedWorkflow: Workflow?
    var englishVoice = "bm_george"

    // MARK: Services
    @ObservationIgnored let brain: Brain
    @ObservationIgnored let records = RecordKeeper.shared
    @ObservationIgnored let speechInput = SpeechInputService()
    @ObservationIgnored let speech = SpeechOutputService()
    let scene = SceneController()
    let hands = HandTrackingService()
    let web = WebAgent()
    let music = MusicService()
    @ObservationIgnored let personal = PersonalDataTools()
    @ObservationIgnored let appleFM = AppleFMEngine()
    let deepThink = DeepThinkEngine()
    @ObservationIgnored let fallback = FallbackEngine()
    @ObservationIgnored var timeEstimator = TimeEstimator()
    @ObservationIgnored lazy var executor = FastCommandExecutor(controller: self)
    @ObservationIgnored lazy var orchestrator = Orchestrator(controller: self)
    @ObservationIgnored lazy var lattice = LatticeSimulator(connectome: brain.connectome)
    @ObservationIgnored var currentRunID: String?
    @ObservationIgnored var currentTask: Task<Void, Never>?
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var latticeTask: Task<Void, Never>?
    @ObservationIgnored private var possibleBargeIn = false
    @ObservationIgnored private var started = false
    @ObservationIgnored var lastInteraction = Date()

    private init() {
        let brain = Brain()
        try? brain.load(from: JarvisPaths.brain)
        self.brain = brain
        fallback.brain = brain
        restoreSettings()
        ToolRegistry.shared.controller = self
        wireServices()
        if let checkpoint = records.latestUnfinishedCheckpoint() {
            var wf = checkpoint.workflow
            wf.markInterrupted()
            interruptedWorkflow = wf
        }
    }

    // MARK: Startup

    /// Called when the app becomes active for the first time.
    func start() {
        guard !started else { return }
        started = true
        // Launch arguments for automated UI smoke tests (e.g. `-JarvisSkipOnboarding YES -JarvisNoMic YES`).
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "JarvisSkipOnboarding") { records.setSetting("onboarded", "1") }
        if defaults.bool(forKey: "JarvisNoMic") { micMuted = true }
        let onboarded = records.setting("onboarded") == "1" || defaults.bool(forKey: "JarvisSkipOnboarding")
        if !onboarded { activePanel = .onboarding }
        // Tell the user (and whoever helps them) why the previous session ended, if it crashed.
        if let report = CrashLog.previousReport {
            let reason = report.split(separator: "\n").prefix(2).joined(separator: " · ")
            appendMessage(.assistant, "\u{26A0}\u{FE0E} 지난 실행이 비정상 종료되었습니다 · Previous session crashed: \(reason)\n(파일 앱 › Jarvis › Logs › previous-crash.txt)",
                          language: currentLanguage)
        }
        Task {
            // Permissions are requested from the onboarding screen, not on first launch.
            if !micMuted && onboarded { await speechInput.start() }
            appleFM.prewarm()
            await loadKokoroIfInstalled()
            await deepThink.loadIfInstalled()
        }
        startLatticeLoop()
        // Scripted conversation for automated end-to-end tests, e.g.
        // `-JarvisScript "open the 3D space || make three red cubes || clone it twice"`.
        if let script = defaults.string(forKey: "JarvisScript"), !script.isEmpty { runScript(script) }
    }

    /// Submits each `||`-separated command in turn, waiting for the previous turn
    /// (and its spoken reply) to finish, exactly as if it had been typed.
    private func runScript(_ script: String) {
        let commands = script.components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            for command in commands {
                guard let self else { return }
                Log.agent.info("Script command: \(command, privacy: .public)")
                self.submit(command, modality: .text)
                var ticks = 0
                while (self.currentTask != nil || self.speech.isSpeaking) && ticks < 40 {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    ticks += 1
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    private func restoreSettings() {
        micMuted = records.setting("micMuted") == "1"
        voiceMuted = records.setting("voiceMuted") == "1"
        if let v = records.setting("voice") { englishVoice = v }
        if let m = records.setting("languageMode").flatMap(LanguageMode.init(rawValue:)) { languageMode = m }
        if let r = records.setting("speechRate").flatMap(Float.init) { speech.rate = r }
        if let t = records.setting("timeEstimator").flatMap({ $0.data(using: .utf8) }),
           let te = try? JSONDecoder().decode(TimeEstimator.self, from: t) { timeEstimator = te }
        speech.muted = voiceMuted
        speech.englishVoice = englishVoice
        speechInput.languageMode = languageMode
    }

    private func wireServices() {
        speechInput.onWake = { [weak self] match in
            guard let self else { return }
            self.wake(source: .voice)
            if !match.trailingCommand.isEmpty {
                self.submit(match.trailingCommand, modality: .voice, language: match.language)
            }
        }
        speechInput.onPartial = { [weak self] text in
            guard let self else { return }
            self.partialTranscript = text
            self.checkBargeIn(partial: text)
        }
        speechInput.onUtterance = { [weak self] text, language, confidence in
            guard let self else { return }
            self.partialTranscript = ""
            // Ignore our own speech that leaked past the echo canceller.
            if self.speech.isLikelyEcho(text) { return }
            self.submit(text, modality: .voice, language: language, confidence: confidence)
        }
        speechInput.onSpeechActivity = { [weak self] speaking in
            guard let self else { return }
            if speaking && self.speech.isSpeaking { self.possibleBargeIn = true }
        }
        speechInput.onLevel = { [weak self] level in self?.inputLevel = level }
        speechInput.onError = { [weak self] message in self?.statusNote = message }

        speech.onSpeakingChanged = { [weak self] speaking in
            guard let self else { return }
            if speaking {
                self.phase = .speaking
                self.brain.setSpeaking(true)
            } else if self.phase == .speaking {
                self.phase = .listening
                self.brain.setSpeaking(false)
                self.possibleBargeIn = false
            }
        }

        hands.onEvents = { [weak self] events in self?.handleHandEvents(events) }
    }

    // MARK: Wake / sleep

    func wake(source: InputModality, speak: Bool = true) {
        CrashLog.breadcrumb("wake")
        lastInteraction = Date()
        let wasAsleep = !isAwake
        phase = .listening
        brain.wake()
        speechInput.mode = .conversation
        if micMuted == false { Task { await speechInput.start() } }
        if wasAsleep && speak {
            appendMessage(.assistant, Persona.wakeResponse, language: .english)
            records.logMessage(role: "assistant", text: Persona.wakeResponse, language: .english, runID: nil)
            speech.speak(Persona.wakeResponse, language: .english)
        }
        CrashLog.breadcrumb("wake: Apple Intelligence prewarm")
        appleFM.prewarm()
        scheduleIdleSleep()
        CrashLog.breadcrumb("wake: hologram presence")
        PresenceManager.shared.awakeStateChanged(true)
        CrashLog.breadcrumb("awake")
    }

    /// Speak "Jarvis at your service, sir." (typed or repeated wake phrase while already awake).
    func respondToWake() {
        if !isAwake { wake(source: .text, speak: false) }
        speech.stop()
        appendMessage(.assistant, Persona.wakeResponse, language: .english)
        records.logMessage(role: "assistant", text: Persona.wakeResponse, language: .english, runID: nil)
        speech.speak(Persona.wakeResponse, language: .english)
    }

    func sleep() {
        phase = .asleep
        brain.sleep()
        speechInput.mode = .wakeOnly
        partialTranscript = ""
        idleTask?.cancel()
        saveBrain()
        PresenceManager.shared.awakeStateChanged(false)
    }

    /// Return to wake-word listening after a long silence (Jarvis stays active in the background).
    private func scheduleIdleSleep() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, self.isAwake else { return }
                let limit = Double(self.records.setting("idleMinutes").flatMap(Double.init) ?? 5) * 60
                if Date().timeIntervalSince(self.lastInteraction) > limit && !self.speech.isSpeaking && self.currentTask == nil {
                    self.sleep()
                    return
                }
            }
        }
    }

    // MARK: Input

    func submit(_ text: String, modality: InputModality, language: DetectedLanguage? = nil, confidence: Double? = nil) {
        lastInteraction = Date()
        if !isAwake && modality != .voice { wake(source: modality, speak: false) }
        cancelCurrentTurn()
        currentTask = Task { [weak self] in
            await self?.orchestrator.handle(text, modality: modality, languageHint: language, confidence: confidence)
            self?.currentTask = nil
        }
    }

    func choose(_ option: SuggestedOption) {
        records.markOptionChosen(option.id)
        submit(option.utterance, modality: .button)
    }

    /// Stop speaking and cancel any running generation (barge-in / new command).
    func cancelCurrentTurn() {
        if speech.isSpeaking { orchestrator.noteInterruption() }
        speech.stop()
        currentTask?.cancel()
        currentTask = nil
    }

    private func checkBargeIn(partial: String) {
        guard possibleBargeIn, speech.isSpeaking else { return }
        let words = partial.split(separator: " ").count
        let hangul = partial.unicodeScalars.filter { Hangul.isSyllable($0) }.count
        guard words >= 2 || hangul >= 3 else { return }
        // Reject our own echo that slipped past the echo canceller.
        if speech.isLikelyEcho(partial) { return }
        possibleBargeIn = false
        cancelCurrentTurn()
        phase = .listening
    }

    // MARK: Toggles

    func setMicMuted(_ muted: Bool) {
        micMuted = muted
        records.setSetting("micMuted", muted ? "1" : "0")
        if muted { speechInput.stop() } else { Task { await speechInput.start() } }
        PresenceManager.shared.refresh()
    }

    func setVoiceMuted(_ muted: Bool) {
        voiceMuted = muted
        speech.muted = muted
        if muted { speech.stop() }
        records.setSetting("voiceMuted", muted ? "1" : "0")
    }

    func setSpaceOpen(_ open: Bool) {
        withAnimation(.easeInOut(duration: 0.45)) { spaceOpen = open }
        if !open && handTrackingEnabled { Task { await setHandTracking(false) } }
    }

    func setHandTracking(_ on: Bool) async {
        handTrackingEnabled = on
        if on { await hands.start() } else { hands.stop() }
        if on && !hands.isRunning { handTrackingEnabled = false }
    }

    func showPanel(_ panel: Panel?) {
        withAnimation(.spring(duration: 0.35)) { activePanel = panel }
    }

    func setLanguageMode(_ mode: LanguageMode) {
        languageMode = mode
        speechInput.languageMode = mode
        records.setSetting("languageMode", mode.rawValue)
        if mode == .korean { currentLanguage = .korean }
        if mode == .english { currentLanguage = .english }
    }

    func setEnglishVoice(_ voice: String) {
        englishVoice = voice
        speech.englishVoice = voice
        records.setSetting("voice", voice)
    }

    func adjustSpeechRate(faster: Bool) {
        brain.adjustSpeechRate(faster: faster)
        speech.rate = max(0.7, min(1.35, speech.rate + (faster ? 0.1 : -0.1)))
        records.setSetting("speechRate", String(speech.rate))
    }

    // MARK: Messages

    @discardableResult
    func appendMessage(_ role: ChatMessage.Role, _ text: String, language: DetectedLanguage, streaming: Bool = false) -> UUID {
        let m = ChatMessage(role: role, text: text, language: language, isStreaming: streaming)
        messages.append(m)
        if messages.count > 200 { messages.removeFirst(messages.count - 200) }
        return m.id
    }

    func updateMessage(_ id: UUID, text: String, streaming: Bool) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[i].text = text
        messages[i].isStreaming = streaming
    }

    // MARK: Hand gestures → 3D space

    private func handleHandEvents(_ events: [HandGestureEvent]) {
        guard spaceOpen, let view = scene.arView else { return }
        let size = view.bounds.size
        func point(_ p: Point2) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
        for e in events {
            switch e {
            case .pointer(let p):
                scene.reticle = point(p)
                scene.reticlePinching = false
                scene.hover(at: point(p))
            case .grabBegan(let p):
                scene.reticle = point(p)
                scene.reticlePinching = true
                _ = scene.beginDrag(at: point(p))
            case .grabMoved(let p):
                scene.reticle = point(p)
                scene.drag(to: point(p))
            case .grabEnded:
                scene.reticlePinching = false
                scene.endDrag()
            case .twoHandBegan:
                scene.beginTwoHandGesture()
            case .twoHandScale(let ratio):
                scene.twoHandGesture(scaleRatio: Float(ratio), rotationRadians: nil)
            case .twoHandRotate(let angle):
                scene.twoHandGesture(scaleRatio: nil, rotationRadians: Float(angle))
            case .twoHandEnded:
                scene.endTwoHandGesture()
            case .handsLost:
                scene.reticle = nil
                scene.endDrag()
            }
        }
    }

    // MARK: Models

    func installKokoro() {
        kokoroStatus = "Downloading…"
        kokoroProgress = 0
        Task {
            do {
                try await KokoroEngine.shared.install { p in
                    Task { @MainActor in self.kokoroProgress = p }
                }
                kokoroProgress = nil
                await loadKokoroIfInstalled()
            } catch {
                kokoroProgress = nil
                kokoroStatus = "Failed: \(error.localizedDescription)"
            }
        }
    }

    func loadKokoroIfInstalled() async {
        guard KokoroEngine.isInstalled else {
            kokoroStatus = "Not installed (system voice in use)"
            return
        }
        do {
            if await !KokoroEngine.shared.isReady { try await KokoroEngine.shared.load() }
            speech.setKokoroReady(true)
            kokoroStatus = "Ready — \(englishVoice)"
        } catch {
            speech.setKokoroReady(false)
            kokoroStatus = "Load failed: \(error.localizedDescription)"
        }
    }

    // MARK: Workflows

    func resumeInterruptedWorkflow() async -> Bool {
        guard let wf = interruptedWorkflow else { return false }
        interruptedWorkflow = nil
        await orchestrator.resume(wf)
        return true
    }

    // MARK: Neural lattice (visualisation + background activity)

    private func startLatticeLoop() {
        latticeTask?.cancel()
        latticeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self else { return }
                let budget = self.brain.hypothalamus.budget(for: DeviceState.body())
                let events = self.activePanel == .brain ? min(budget.latticeEventsPerTick, 60_000) : min(budget.latticeEventsPerTick, 4_000)
                guard events > 0 else { continue }
                let stats = self.lattice.step(eventBudget: events, synapsesPerSpike: 48)
                if self.activePanel == .brain {
                    self.latticeStats = stats
                    self.latticeSample = stats.sample
                }
            }
        }
    }

    func stimulateLattice(_ ids: [NeuronID]) {
        lattice.inject(ids)
    }

    func saveBrain() {
        try? brain.save(to: JarvisPaths.brain)
        if let data = try? JSONEncoder().encode(timeEstimator), let s = String(data: data, encoding: .utf8) {
            records.setSetting("timeEstimator", s)
        }
    }

    /// Refine the heuristic language detection with Apple's NaturalLanguage framework.
    func detectLanguage(_ text: String) -> DetectedLanguage {
        let core = LanguageDetector.detect(text, previous: currentLanguage)
        if core.confidence >= 0.6 { return core.language }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.korean, .english]
        recognizer.processString(text)
        switch recognizer.dominantLanguage {
        case .korean?: return .korean
        case .english?: return .english
        default: return core.language
        }
    }
}
