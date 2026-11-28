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
    case history, brain, settings, browser, help, onboarding, studio
    var id: String { rawValue }
}

/// A tap-to-open button under a chat message (an app, call or message iOS refused to open
/// programmatically; a tap by the user is often allowed where code is not).
struct ChatLink: Equatable {
    var url: URL
    var title: String
}

struct ChatMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant, system }
    var id = UUID()
    var role: Role
    var text: String
    var language: DetectedLanguage
    var timestamp = Date()
    var isStreaming = false
    var link: ChatLink?
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
    @ObservationIgnored private var pendingLink: ChatLink?
    var statusNote = ""
    var latticeSample: [NeuronID] = []
    var latticeStats: LatticeTickStats?
    var kokoroStatus = "—"
    var kokoroProgress: Double?
    var interruptedWorkflow: Workflow?
    var englishVoice = "bm_george"

    // MARK: Input status (shown under the chat input)
    /// A request (typed, spoken or tapped) is being carried out.
    var busy = false
    /// The text field has focus (the HUD calms its animations meanwhile).
    var typing = false
    /// There is unsent text in the field: speech not addressed to Jarvis is set aside meanwhile
    /// (the microphone hears the keyboard). An empty, focused field doesn't block speech.
    var composing = false
    var voiceState: SpeechInputService.State = .off
    /// The last words the microphone delivered to Jarvis.
    var lastHeard = ""
    /// Why the last speech was set aside, or a microphone problem.
    var voiceNote = ""
    var pushToTalkActive = false
    @ObservationIgnored private var lastTypingActivity = Date.distantPast
    @ObservationIgnored private var lastUtteranceText = ""
    @ObservationIgnored private var lastUtteranceTime = Date.distantPast
    @ObservationIgnored private var queuedVoice: [(text: String, language: DetectedLanguage?, confidence: Double?)] = []
    @ObservationIgnored private var turnStarted = Date.distantPast
    @ObservationIgnored private var turnToken = UUID()
    @ObservationIgnored private var currentTurnModality: InputModality?
    @ObservationIgnored private var lastLevelUpdate = Date.distantPast
    @ObservationIgnored private var shownNotes: [String: Date] = [:]
    @ObservationIgnored private var stallTimer: Timer?
    @ObservationIgnored private var lastTick = CFAbsoluteTimeGetCurrent()
    /// Longest main-thread stall seen (seconds), for diagnostics and the CI input test.
    @ObservationIgnored private(set) var worstStall: Double = 0

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
        wireStudio()
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
        if defaults.bool(forKey: "JarvisResetScene") { scene.clear() }
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
            CrashLog.breadcrumb("launch: speech input")
            if !micMuted && onboarded { await speechInput.start() }
            CrashLog.breadcrumb("launch: Apple Intelligence prewarm")
            appleFM.prewarm()
            CrashLog.breadcrumb("launch: Kokoro")
            await loadKokoroIfInstalled()
            CrashLog.breadcrumb("launch: deep think")
            await deepThink.loadIfInstalled()
            CrashLog.breadcrumb("launch: done")
        }
        CrashLog.breadcrumb("launch: lattice")
        startLatticeLoop()
        startStallMonitor()
        // Automated tests of the real input paths: typing into the actual text field, and speech
        // results fed through the same gate as the microphone's.
        if let text = defaults.string(forKey: "JarvisTypeTest"), !text.isEmpty { runTypeTest(text) }
        if let text = defaults.string(forKey: "JarvisVoiceTest"), !text.isEmpty { runVoiceTest(text) }
        if let text = defaults.string(forKey: "JarvisAudioTest"), !text.isEmpty { runAudioTest(text) }
        if let text = defaults.string(forKey: "JarvisStudioTest"), !text.isEmpty { runStudioTest(text) }
        // Scripted conversation for automated end-to-end tests, e.g.
        // `-JarvisScript "open the 3D space || make three red cubes || clone it twice"`.
        if let script = defaults.string(forKey: "JarvisScript"), !script.isEmpty { runScript(script) }
        // Automated test of the onboarding "Begin" button (wake with speech and microphone).
        if defaults.bool(forKey: "JarvisPressBegin") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.completeOnboarding()
            }
        }
        // Automated test of the emergency wake button (pressed twice: asleep, then awake).
        if defaults.bool(forKey: "JarvisPressEmergency") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.emergencyWake()
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                self?.emergencyWake()
            }
        }
    }

    /// The app came to the foreground: make sure Jarvis is listening again.
    func appBecameActive() {
        start()
        guard records.setting("onboarded") == "1", !micMuted else { return }
        speechInput.ensureListening()
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
                // Up to 30 s per command (finding and loading a song takes a while).
                while (self.currentTask != nil || self.speech.isSpeaking) && ticks < 120 {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    ticks += 1
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    /// Studio results reach the conversation like any other reply: what was made, the link for
    /// web products, the problems found if any.
    private func wireStudio() {
        StudioController.shared.onFinished = { [weak self] request, outcome, link in
            guard let self else { return }
            let language: DetectedLanguage = request.korean ? .korean : .english
            var text = outcome.summary
            let problems = outcome.checks.filter { $0.hasPrefix("✗") }
            if !problems.isEmpty { text += "\n" + problems.prefix(3).joined(separator: "\n") }
            self.appendMessage(.assistant, text, language: language)
            self.records.logMessage(role: "assistant", text: text, language: language, runID: nil)
            if let link { self.offerLink(link, title: request.korean ? "결과물 열기" : "Open the result") }
            if outcome.ok {
                let spoken = request.korean ? "완성했습니다. 스튜디오에서 바로 확인하실 수 있습니다." : "It's ready, sir. You can try it in the studio now."
                self.speech.speak(spoken, language: language)
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
        CommandGrammar.isKnownApp = { (name: String) -> Bool in AppCatalog.find(name) != nil }
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
            self.handleHeard(text, language: language, confidence: confidence)
        }
        speechInput.onState = { [weak self] state in
            guard let self else { return }
            self.voiceState = state
            let name: String = String(describing: state)
            Log.voice.info("Voice state: \(name, privacy: .public)")
        }
        speechInput.onNothingHeard = { [weak self] in
            guard let self else { return }
            let ko = self.currentLanguage == .korean
            self.appendMessage(.assistant, ko ? "잘 듣지 못했습니다. 버튼을 누른 채로 다시 말씀해 주십시오." : "I didn't catch that, sir. Hold the button while you speak.", language: self.currentLanguage)
        }
        speechInput.onSpeechActivity = { [weak self] speaking in
            guard let self else { return }
            if speaking && self.speech.isSpeaking { self.possibleBargeIn = true }
        }
        speechInput.onLevel = { [weak self] level in self?.updateLevel(level) }
        speechInput.onError = { [weak self] message in self?.reportVoiceProblem(message) }

        speech.onSpeakingChanged = { [weak self] speaking in
            guard let self else { return }
            let state: String = speaking ? "started" : "ended"
            Log.voice.info("Speaking \(state, privacy: .public)")
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

    /// Addressed by name, or a command the grammar recognises clearly ("pause", "다음 곡").
    static func isMeantForJarvis(_ text: String) -> Bool {
        let lower: String = text.lowercased()
        let names: [String] = ["jarvis", "자비스", "쟈비스", "재비스"]
        if names.contains(where: { lower.contains($0) }) { return true }
        let parsed = CommandGrammar().parse(text)
        return !parsed.isEmpty && parsed.confidence >= 0.8
    }

    // MARK: Wake / sleep

    func wake(source: InputModality, speak: Bool = true) {
        CrashLog.breadcrumb("wake")
        lastInteraction = Date()
        let wasAsleep = !isAwake
        phase = .listening
        brain.wake()
        speechInput.mode = .conversation
        if !micMuted { speechInput.ensureListening() }
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

    /// The onboarding "Begin" button: remember onboarding, close the card and wake up.
    func completeOnboarding() {
        CrashLog.breadcrumb("onboarding: begin")
        records.setSetting("onboarded", "1")
        showPanel(nil)
        wake(source: .button)
    }

    /// Speak "Jarvis at your service, sir." — always, even when already awake
    /// (typed or repeated wake phrase, emergency button).
    func respondToWake(source: InputModality = .text) {
        if !isAwake {
            wake(source: source, speak: false)
        } else {
            lastInteraction = Date()
            scheduleIdleSleep()
        }
        speech.stop()
        appendMessage(.assistant, Persona.wakeResponse, language: .english)
        records.logMessage(role: "assistant", text: Persona.wakeResponse, language: .english, runID: nil)
        speech.speak(Persona.wakeResponse, language: .english)
        let from: String = source.rawValue
        Log.agent.info("Wake response (\(from, privacy: .public))")
    }

    /// The emergency wake button: always answers and makes sure Jarvis is listening
    /// again — the dependable way back when the voice wake did not catch.
    func emergencyWake() {
        CrashLog.breadcrumb("emergency wake")
        Log.agent.info("Emergency wake pressed")
        if activePanel == .onboarding {
            records.setSetting("onboarded", "1")
            showPanel(nil)
        }
        cancelCurrentTurn()
        // Fresh recognition sessions (and a restarted microphone if it had stopped).
        if !micMuted { speechInput.ensureListening(restart: true) }
        respondToWake(source: .button)
    }

    /// Answer Jarvis' "Shall I …?" question with the on-screen Yes / No buttons.
    func answerConfirmation(_ yes: Bool) {
        let ko: Bool = currentLanguage == .korean
        let answer: String = yes ? (ko ? "네" : "Yes") : (ko ? "아니요" : "No")
        submit(answer, modality: .button, language: currentLanguage)
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
                let limit = Double(self.records.setting("idleMinutes").flatMap(Double.init) ?? 10) * 60
                if Date().timeIntervalSince(self.lastInteraction) > limit && !self.speech.isSpeaking && self.currentTask == nil {
                    self.sleep()
                    return
                }
            }
        }
    }

    // MARK: Input

    func submit(_ text: String, modality: InputModality, language: DetectedLanguage? = nil, confidence: Double? = nil) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        lastInteraction = Date()
        pendingLink = nil
        if !isAwake && modality != .voice { wake(source: modality, speak: false) }
        // Speech never cancels a typed or tapped request that is still being carried out (the
        // microphone hears keyboard clicks and Jarvis itself); it waits its turn. "Stop" interrupts,
        // and so does any speech once the request has run for 20 s (it must never trap the voice).
        let turnAge: Double = Date().timeIntervalSince(turnStarted)
        if modality == .voice, currentTask != nil, let running = currentTurnModality, running != .voice,
           !VoiceGate.isStopCommand(clean), turnAge < 20 {
            queuedVoice.append((clean, language, confidence))
            Log.voice.info("Voice input queued behind a typed request")
            return
        }
        cancelCurrentTurn()
        // Show the request at once: input visibly works even while it is being carried out.
        let shown: DetectedLanguage
        switch languageMode {
        case .korean: shown = .korean
        case .english: shown = .english
        case .auto: shown = language ?? detectLanguage(clean)
        }
        appendMessage(.user, clean, language: shown)
        let token = UUID()
        turnToken = token
        turnStarted = Date()
        currentTurnModality = modality
        busy = true
        let started = Date()
        currentTask = Task { [weak self] in
            await self?.orchestrator.handle(clean, modality: modality, languageHint: language, confidence: confidence, alreadyShown: true)
            guard let self, self.turnToken == token else { return }
            self.currentTask = nil
            self.currentTurnModality = nil
            self.busy = false
            let secs = String(format: "%.2f", Date().timeIntervalSince(started))
            let source: String = modality.rawValue
            Log.agent.info("Input handled (\(source, privacy: .public)) in \(secs, privacy: .public)s")
            if !self.queuedVoice.isEmpty {
                let next = self.queuedVoice.removeFirst()
                self.submit(next.text, modality: .voice, language: next.language, confidence: next.confidence)
            }
        }
    }

    /// Speech from the microphone: through the voice gate, then like any other input.
    private func handleHeard(_ text: String, language: DetectedLanguage, confidence: Double) {
        let context = voiceContext()
        if case .drop(let reason) = VoiceGate.utterance(text, confidence: confidence, context: context) {
            Log.voice.info("Voice gate: dropped (\(reason, privacy: .public))")
            voiceNote = reason
            return
        }
        // While a song plays the microphone hears it too: only take speech meant for Jarvis.
        let answersQuestion: Bool = pendingConfirmation != nil && ConfirmationReply.classify(text) != nil
        if music.isPlaying && !answersQuestion && !context.pushToTalk && !JarvisController.isMeantForJarvis(text) {
            Log.voice.info("Voice gate: dropped (music)")
            voiceNote = "music"
            return
        }
        lastUtteranceText = text
        lastUtteranceTime = Date()
        lastHeard = text
        voiceNote = ""
        Log.voice.info("Voice gate: accepted")
        submit(text, modality: .voice, language: language, confidence: confidence)
    }

    private func voiceContext() -> VoiceGate.Context {
        var c = VoiceGate.Context()
        c.jarvisSpeaking = speech.isSpeaking
        c.secondsSinceSpeechEnded = speech.secondsSinceSpeechEnded
        c.spokenRecently = speech.recentSpokenText(within: 8)
        c.typing = composing || Date().timeIntervalSince(lastTypingActivity) < 2.5
        c.pushToTalk = speechInput.pushToTalkActive
        c.secondsSinceLastUtterance = Date().timeIntervalSince(lastUtteranceTime)
        c.lastUtterance = lastUtteranceText
        c.userInterrupted = Date().timeIntervalSince(lastSpeechInterruption) < 4
        return c
    }

    /// The text field gained or lost focus.
    func setTyping(_ on: Bool) {
        if typing != on { typing = on }
    }

    /// The text in the field changed.
    func noteTyping(hasText: Bool) {
        lastTypingActivity = Date()
        if composing != hasText { composing = hasText }
    }

    /// Hold-to-talk: listen while the button is held, then carry out what was said.
    func pushToTalk(_ down: Bool) {
        if down {
            guard !pushToTalkActive else { return }
            pushToTalkActive = true
            speech.stop()
            voiceNote = ""
            if micMuted { setMicMuted(false) }
            if !isAwake { wake(source: .button, speak: false) }
            speechInput.mode = .conversation
            speechInput.beginPushToTalk()
        } else {
            guard pushToTalkActive else { return }
            pushToTalkActive = false
            speechInput.endPushToTalk()
        }
    }

    /// Mic level for the HUD, at most ~10 updates a second (each one redraws views).
    private func updateLevel(_ level: Float) {
        let now = Date()
        let change: Float = abs(level - inputLevel)
        guard change > 0.02, now.timeIntervalSince(lastLevelUpdate) > 0.1 || change > 0.3 else { return }
        lastLevelUpdate = now
        inputLevel = level
    }

    /// A microphone or recognition problem: say so in the conversation (not only in a log), with a
    /// way to fix it.
    private func reportVoiceProblem(_ message: String) {
        statusNote = message
        voiceNote = message
        let now = Date()
        if let last = shownNotes[message], now.timeIntervalSince(last) < 120 { return }
        shownNotes[message] = now
        Log.voice.error("Voice problem shown to the user")
        if voiceState == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
            offerLink(url, title: currentLanguage == .korean ? "설정 열기" : "Open Settings")
        }
        appendMessage(.assistant, "⚠︎ " + message, language: currentLanguage)
    }

    func choose(_ option: SuggestedOption) {
        records.markOptionChosen(option.id)
        submit(option.utterance, modality: .button)
    }

    /// When the user last cut Jarvis off mid-sentence.
    @ObservationIgnored var lastSpeechInterruption = Date.distantPast

    /// Stop speaking and cancel any running generation (barge-in / new command).
    func cancelCurrentTurn() {
        if speech.isSpeaking {
            orchestrator.noteInterruption()
            lastSpeechInterruption = Date()
        }
        speech.stop()
        currentTask?.cancel()
        currentTask = nil
        currentTurnModality = nil
        turnToken = UUID()
        busy = false
    }

    private func checkBargeIn(partial: String) {
        guard speech.isSpeaking else { return }
        // Only a real interruption ("stop", "Jarvis", a clearly different sentence) cuts Jarvis
        // off; its own voice coming back through the microphone does not.
        guard speechInput.pushToTalkActive || (possibleBargeIn && VoiceGate.bargeIn(partial: partial, context: voiceContext())) else { return }
        possibleBargeIn = false
        Log.voice.info("Barge-in: stopped speaking")
        cancelCurrentTurn()
        phase = .listening
    }

    /// Tapping the core: wake up, or (already awake) listen afresh. It never puts Jarvis to sleep —
    /// that used to silence the microphone for anyone tapping the ▷ core to talk.
    func coreTapped() {
        if !isAwake {
            wake(source: .button)
            return
        }
        lastInteraction = Date()
        speech.stop()
        if micMuted { setMicMuted(false) } else { speechInput.ensureListening(restart: true) }
        voiceNote = ""
        Log.voice.info("Core tapped: listening afresh")
    }

    // MARK: Toggles

    func setMicMuted(_ muted: Bool) {
        micMuted = muted
        records.setSetting("micMuted", muted ? "1" : "0")
        if muted { speechInput.stop() } else { speechInput.ensureListening() }
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

    /// Attach a tap-to-open button to Jarvis' next reply.
    func offerLink(_ url: URL?, title: String) {
        guard let url else { return }
        pendingLink = ChatLink(url: url, title: title)
    }

    @discardableResult
    func appendMessage(_ role: ChatMessage.Role, _ text: String, language: DetectedLanguage, streaming: Bool = false) -> UUID {
        var m = ChatMessage(role: role, text: text, language: language, isStreaming: streaming)
        if role == .assistant, let link = pendingLink {
            m.link = link
            pendingLink = nil
        }
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

    // MARK: Diagnostics

    /// Logs whenever the main thread (UI, keyboard, speech callbacks) is blocked for long.
    private func startStallMonitor() {
        stallTimer?.invalidate()
        lastTick = CFAbsoluteTimeGetCurrent()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stallTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        stallTimer = timer
    }

    private func stallTick() {
        let now = CFAbsoluteTimeGetCurrent()
        let late = now - lastTick - 0.25
        lastTick = now
        if late > worstStall { worstStall = late }
        if late > 0.6 {
            let secs = String(format: "%.2f", late)
            let p: String = phase.rawValue
            let last: String = CrashLog.lastMainStep
            let other: String = CrashLog.lastBreadcrumb
            Log.agent.error("Main thread stalled for \(secs, privacy: .public)s (phase \(p, privacy: .public), last main-thread step: \(last, privacy: .public); last step anywhere: \(other, privacy: .public))")
            CrashLog.breadcrumb("main thread stalled \(secs)s", step: false)
        }
    }

    /// CI: type into the real text field through UIKit (focus, keystrokes, Return) and report each step.
    private func runTypeTest(_ text: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self else { return }
            guard let field = Self.findTextField() else {
                Log.agent.error("Type test: field=false")
                return
            }
            let window = field.window
            let center: CGPoint = field.convert(CGPoint(x: field.bounds.midX, y: field.bounds.midY), to: window)
            let hit: UIView? = window?.hitTest(center, with: nil)
            let tappable: Bool = hit.map { $0 === field || $0.isDescendant(of: field) } ?? false
            self.worstStall = 0   // count stalls while interacting, not during launch
            let focused: Bool = field.becomeFirstResponder()
            try? await Task.sleep(nanoseconds: 700_000_000)
            field.insertText(text)
            try? await Task.sleep(nanoseconds: 500_000_000)
            let typed: Bool = (field.text ?? "") == text
            _ = field.delegate?.textFieldShouldReturn?(field)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            var submitted: Bool = self.messages.contains { $0.role == .user && $0.text == text }
            var method = "return key"
            if !submitted {
                field.sendActions(for: .editingDidEndOnExit)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                submitted = self.messages.contains { $0.role == .user && $0.text == text }
                method = "end-on-exit"
            }
            let key: Bool = window?.isKeyWindow ?? false
            let hitName: String = hit.map { String(describing: type(of: $0)) } ?? "nil"
            Log.agent.info("Type test: field=true tappable=\(tappable, privacy: .public) hit=\(hitName, privacy: .public) keyWindow=\(key, privacy: .public) focused=\(focused, privacy: .public) typed=\(typed, privacy: .public) submitted=\(submitted, privacy: .public) via=\(method, privacy: .public)")
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            let worst = String(format: "%.2f", self.worstStall)
            Log.agent.info("Main thread: worst stall \(worst, privacy: .public)s")
        }
    }

    static func findTextField() -> UITextField? {
        func search(_ view: UIView) -> UITextField? {
            if let f = view as? UITextField, !f.isHidden, f.isUserInteractionEnabled { return f }
            for sub in view.subviews { if let f = search(sub) { return f } }
            return nil
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows where !(window is PassthroughWindow) {
                if let f = search(window) { return f }
            }
        }
        return nil
    }

    /// CI: feed recognised speech through the same gate as the microphone: a command, Jarvis' own
    /// echo, and a command addressed by name while asleep.
    private func runVoiceTest(_ text: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000_000)
            guard let self else { return }
            if !self.isAwake { self.wake(source: .button, speak: false) }
            self.speechInput.mode = .conversation
            // Like a person, let Jarvis finish its sentence first (at most 15 s).
            var waited = 0
            while (self.speech.isSpeaking || self.busy) && waited < 150 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            self.speechInput.simulateHeard(text, language: .english)
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            let heard: Bool = self.messages.contains { $0.role == .user && $0.text == text }
            Log.agent.info("Voice test: command delivered=\(heard, privacy: .public)")
            // Talking over Jarvis with a different sentence is the user, not an echo.
            self.speech.stop()
            let talk = "The forecast for tomorrow is cloudy with light rain, sir."
            self.speech.speak(talk, language: .english)
            try? await Task.sleep(nanoseconds: 400_000_000)
            let over = "make a green cone"
            let speakingThen: Bool = self.speech.isSpeaking
            self.speechInput.simulateHeard(over, language: .english)
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            let overHeard: Bool = self.messages.contains { $0.role == .user && $0.text == over }
            Log.agent.info("Voice test: command while speaking delivered=\(overHeard, privacy: .public) (speaking=\(speakingThen, privacy: .public))")
            waited = 0
            while (self.speech.isSpeaking || self.busy) && waited < 150 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
            // Jarvis' own words coming back through the microphone must be ignored.
            let echo = "I have finished the task you asked for, sir."
            self.speech.speak(echo, language: .english)
            try? await Task.sleep(nanoseconds: 300_000_000)
            let before = self.messages.count
            self.speechInput.simulateHeard(echo, language: .english)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let echoIgnored: Bool = !self.messages.dropFirst(before).contains { $0.role == .user }
            Log.agent.info("Voice test: echo ignored=\(echoIgnored, privacy: .public)")
            self.speech.stop()
            // Asleep, "Jarvis, …" still works.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.sleep()
            let named = "Jarvis open the 3D space"
            self.speechInput.simulateHeard(named, language: .english)
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            let woke: Bool = self.isAwake && self.spaceOpen
            Log.agent.info("Voice test: named command while asleep=\(woke, privacy: .public)")
        }
    }

    /// CI: real speech recognition. A sentence spoken by the system voice is fed to the
    /// recognisers in place of the microphone; it must come out as a command that runs.
    private func runAudioTest(_ text: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self else { return }
            if !self.isAwake { self.wake(source: .button, speak: false) }
            self.speechInput.mode = .conversation
            guard self.speechInput.startFeedOnly() else {
                Log.agent.info("Audio test: recognition not authorised here")
                return
            }
            self.speechInput.onTestHeard = { heard in
                Log.agent.info("Audio test: the recognisers heard '\(heard, privacy: .public)'")
            }
            let clip = await AudioTestSupport.microphoneLikeClip(text, language: .english)
            let secs = String(format: "%.1f", clip.speechSeconds)
            Log.agent.info("Audio test: rendered \(secs, privacy: .public)s of speech in \(clip.buffers.count, privacy: .public) buffers")
            // Room noise first, as a live microphone would give, so the recognisers settle.
            let quiet = await AudioTestSupport.microphoneLikeClip("", language: .english, quietSeconds: 3)
            await self.speechInput.feedTestAudio(quiet.buffers)
            let before = self.messages.count
            let fed = Date()
            await self.speechInput.feedTestAudio(clip.buffers)
            let feedSecs = String(format: "%.1f", Date().timeIntervalSince(fed))
            Log.agent.info("Audio test: fed the speech in \(feedSecs, privacy: .public)s")
            var waited = 0
            while waited < 120 && !self.messages.dropFirst(before).contains(where: { $0.role == .user }) {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
            let heard: String = self.messages.dropFirst(before).first(where: { $0.role == .user })?.text ?? ""
            let key: String = text.split(separator: " ").last.map { String($0).lowercased() } ?? text
            let delivered: Bool = heard.lowercased().contains(key)
            Log.agent.info("Audio test: recognised '\(heard, privacy: .public)' delivered=\(delivered, privacy: .public)")
        }
    }

    /// CI: the studio end to end, driven like a user — a typed request builds a product that is
    /// checked in WebKit and served on the local link; a stacked adjustment rebuilds it; it is
    /// exported as a Windows program.
    private func runStudioTest(_ text: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self else { return }
            let studio = StudioController.shared
            let ws = studio.newWorkspace("CI \(Int(Date().timeIntervalSince1970) % 100000)")
            self.submit(text, modality: .text)
            let first = await Self.waitForRequest(studio, ws.id, index: 0)
            let link: URL? = studio.shareLink
            var served = false
            if let link, let (data, response) = try? await URLSession.shared.data(from: link) {
                let code: Int = (response as? HTTPURLResponse)?.statusCode ?? 0
                served = code == 200 && String(decoding: data, as: UTF8.self).lowercased().contains("<html")
            }
            let status1: String = first?.status.rawValue ?? "none"
            let linkText: String = link?.absoluteString ?? "none"
            let panelOpen: Bool = self.activePanel == .studio
            Log.agent.info("Studio test: status=\(status1, privacy: .public) version=\(first?.version ?? 0, privacy: .public) panel=\(panelOpen, privacy: .public) served=\(served, privacy: .public) link=\(linkText, privacy: .public)")
            Log.agent.info("Studio test: checks \((first?.checks ?? []).joined(separator: " | "), privacy: .public)")
            // A stacked adjustment, said the way a user would while the studio is open.
            self.submit("make the snake faster and add a timer", modality: .text)
            let second = await Self.waitForRequest(studio, ws.id, index: 1)
            let status2: String = second?.status.rawValue ?? "none"
            let config: String = (try? studio.store.files(ws.id).readText("/config.js")) ?? ""
            let adjusted: Bool = config.contains("\"timer\": true") && config.contains("\"speed\": 1.")
            Log.agent.info("Studio test: adjustment status=\(status2, privacy: .public) version=\(second?.version ?? 0, privacy: .public) applied=\(adjusted, privacy: .public)")
            await studio.deliver(as: "exe")
            let exeBytes: Int = studio.delivery.flatMap { try? Data(contentsOf: $0.url).count } ?? 0
            let starts: Bool = studio.delivery.flatMap { try? Data(contentsOf: $0.url).prefix(2) } == Data("MZ".utf8)
            Log.agent.info("Studio test: exe=\(studio.delivery?.title ?? "none", privacy: .public) bytes=\(exeBytes, privacy: .public) windowsProgram=\(starts, privacy: .public)")
        }
    }

    private static func waitForRequest(_ studio: StudioController, _ id: String, index: Int) async -> WorkRequest? {
        for _ in 0..<600 {
            let requests: [WorkRequest] = studio.store.workspace(id)?.requests ?? []
            if requests.count > index, requests[index].status == .done || requests[index].status == .failed { return requests[index] }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let requests: [WorkRequest] = studio.store.workspace(id)?.requests ?? []
        return requests.count > index ? requests[index] : nil
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
                CrashLog.breadcrumb("lattice step")
                let stats = self.lattice.step(eventBudget: events, synapsesPerSpike: 48)
                CrashLog.breadcrumb("main idle")
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
