import SwiftUI
import UIKit

/// Text + voice chat hologram: conversation, live transcript, input field,
/// user-microphone and AI-voice mute toggles, and the 3D-space button.
/// Present on every screen of the app (requirement 16).
struct ChatHologram: View {
    @Environment(JarvisController.self) private var jarvis
    @State private var draft = ""
    @FocusState private var focused: Bool
    var compact = false

    var body: some View {
        VStack(spacing: 8) {
            if !compact {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(jarvis.messages.suffix(40)) { m in
                                MessageBubble(message: m).id(m.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 220)
                    .onChange(of: jarvis.messages.last?.text) { _, _ in
                        if let id = jarvis.messages.last?.id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } }
                    }
                }
            }
            // Live transcript and status in their own small views, so frequent updates from the
            // recogniser don't re-render the whole chat (and the text field) each time.
            PartialTranscriptRow()
            if jarvis.pendingConfirmation != nil { confirmationBar }
            InputStatusLine()
            inputBar
        }
        .padding(12)
        .holoPanel()
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            micToggle
            voiceToggle
            inputField
            sendButton
            HoldToTalkButton()
            HoloIconToggle(icon: "cube.transparent", active: jarvis.spaceOpen, tint: Holo.amber, label: "3D") {
                jarvis.setSpaceOpen(!jarvis.spaceOpen)
            }
        }
    }

    private var micToggle: some View {
        let muted: Bool = jarvis.micMuted
        return HoloIconToggle(icon: muted ? "mic.slash.fill" : "mic.fill", active: !muted,
                              tint: muted ? Holo.red : Holo.cyan, label: muted ? "MIC OFF" : "MIC") {
            jarvis.setMicMuted(!muted)
        }
    }

    private var voiceToggle: some View {
        let muted: Bool = jarvis.voiceMuted
        return HoloIconToggle(icon: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", active: !muted,
                              tint: muted ? Holo.red : Holo.cyan, label: muted ? "AI MUTED" : "VOICE") {
            jarvis.setVoiceMuted(!muted)
        }
    }

    private var placeholder: String {
        jarvis.currentLanguage == .korean ? "자비스에게 말하거나 입력하십시오…" : "Speak or type to Jarvis…"
    }

    private var inputField: some View {
        let border: Color = Holo.cyan.opacity(focused ? 0.8 : 0.3)
        return ZStack(alignment: .leading) {
            if draft.isEmpty {
                Text(placeholder)
                    .font(Holo.mono(13))
                    .foregroundStyle(Holo.ice.opacity(0.4))
            }
            // Single line: Return (software or hardware keyboard) sends. A vertical text field
            // would insert a newline instead and never submit.
            TextField("", text: $draft)
                .font(Holo.mono(14))
                .foregroundStyle(.white)
                .focused($focused)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .onSubmit(send)
                .onChange(of: focused) { _, on in jarvis.setTyping(on) }
                .onChange(of: draft) { _, _ in jarvis.noteTyping() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border))
    }

    private var sendButton: some View {
        let empty: Bool = draft.isEmpty
        let blank: Bool = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let tint: Color = empty ? Holo.ice.opacity(0.3) : Holo.cyan
        let glow: Color = empty ? Color.clear : Holo.cyan
        return Button(action: send) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(tint)
                .holoGlow(glow, radius: 6)
        }
        .buttonStyle(.plain)
        .disabled(blank)
        .keyboardShortcut(.return, modifiers: .command)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        jarvis.submit(text, modality: .text)
        // Keep the keyboard up for the next message.
        focused = true
    }

    /// Yes / No buttons while Jarvis waits for a confirmation ("Shall I call …?").
    private var confirmationBar: some View {
        let ko: Bool = jarvis.currentLanguage == .korean
        return HStack(spacing: 10) {
            Image(systemName: "questionmark.circle.fill").foregroundStyle(Holo.amber)
            Text(ko ? "진행할까요?" : "Proceed?")
                .font(Holo.mono(12))
                .foregroundStyle(Holo.ice.opacity(0.9))
            Spacer(minLength: 0)
            Button(ko ? "네" : "Yes") { jarvis.answerConfirmation(true) }
                .buttonStyle(.borderedProminent)
                .tint(Holo.cyan)
            Button(ko ? "아니요" : "No") { jarvis.answerConfirmation(false) }
                .buttonStyle(.bordered)
                .tint(Holo.red)
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
    }
}

struct HoloIconToggle: View {
    let icon: String
    let active: Bool
    var tint: Color = Holo.cyan
    var label: String = ""
    let action: () -> Void
    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        }) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                if !label.isEmpty { Text(label).font(Holo.mono(7, .bold)) }
            }
            .foregroundStyle(active ? tint : Holo.ice.opacity(0.7))
            .frame(width: 50, height: 42)
            .background(RoundedRectangle(cornerRadius: 9).fill(active ? tint.opacity(0.16) : Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(tint.opacity(active ? 0.85 : 0.3)))
            .holoGlow(active ? tint : .clear, radius: 4)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    private func linkButton(_ link: ChatLink) -> some View {
        Link(destination: link.url) {
            Label(link.title, systemImage: "arrow.up.forward.app")
                .font(Holo.mono(11, .bold))
                .foregroundStyle(Holo.deep)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Holo.cyan))
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 3) {
                HUDLabel(text: message.role == .user ? "YOU · \(message.language.rawValue)" : "JARVIS · \(message.language.rawValue)",
                         color: message.role == .user ? Holo.amber : Holo.cyan, size: 8)
                Text(message.text.isEmpty && message.isStreaming ? "…" : message.text)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .textSelection(.enabled)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill((message.role == .user ? Holo.amber : Holo.cyan).opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder((message.role == .user ? Holo.amber : Holo.cyan).opacity(0.35))
                    )
                if let link = message.link { linkButton(link) }
            }
            if message.role != .user { Spacer(minLength: 40) }
        }
    }
}


/// The words being recognised right now.
struct PartialTranscriptRow: View {
    @Environment(JarvisController.self) private var jarvis

    var body: some View {
        let text: String = jarvis.partialTranscript
        if !text.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "waveform").foregroundStyle(Holo.cyan)
                Text(text)
                    .font(Holo.mono(12))
                    .foregroundStyle(Holo.ice.opacity(0.8))
                    .lineLimit(2)
                Spacer()
            }
            .transition(.opacity)
        }
    }
}

/// One line saying what the input side is doing: working on a request, listening, asleep,
/// typing, or a microphone problem with a way to fix it.
struct InputStatusLine: View {
    @Environment(JarvisController.self) private var jarvis

    private struct Status {
        var icon: String
        var text: String
        var color: Color
        var fixSettings = false
    }

    private var status: Status {
        let ko: Bool = jarvis.currentLanguage == .korean
        if jarvis.busy {
            return Status(icon: "hourglass", text: ko ? "요청을 처리하고 있습니다…" : "Working on it…", color: Holo.amber)
        }
        if jarvis.pushToTalkActive {
            return Status(icon: "mic.fill", text: ko ? "듣고 있습니다 — 말씀이 끝나면 버튼에서 손을 떼십시오" : "Listening — let go when you're done", color: Holo.green)
        }
        if jarvis.micMuted {
            return Status(icon: "mic.slash", text: ko ? "마이크가 꺼져 있습니다 — 입력하거나 말하기 버튼을 누르십시오" : "Microphone off — type, or hold TALK", color: Holo.ice.opacity(0.6))
        }
        switch jarvis.voiceState {
        case .denied:
            return Status(icon: "exclamationmark.triangle.fill",
                          text: ko ? "마이크·음성 인식 권한이 꺼져 있습니다" : "Microphone or speech permission is off", color: Holo.red, fixSettings: true)
        case .failed(let why):
            return Status(icon: "exclamationmark.triangle.fill", text: (ko ? "음성 인식 문제: " : "Voice problem: ") + why, color: Holo.red)
        case .starting:
            return Status(icon: "mic", text: ko ? "마이크를 켜는 중…" : "Starting the microphone…", color: Holo.ice.opacity(0.7))
        case .off:
            return Status(icon: "mic.slash", text: ko ? "음성 인식이 꺼져 있습니다 — 말하기 버튼을 길게 누르십시오" : "Voice is off — hold TALK to speak", color: Holo.ice.opacity(0.6))
        case .listening:
            break
        }
        if jarvis.typing {
            return Status(icon: "keyboard", text: ko ? "입력 중 — \"자비스\"로 부르는 말만 음성으로 받습니다" : "Typing — speech only counts when it starts with \"Jarvis\"", color: Holo.ice.opacity(0.6))
        }
        if !jarvis.isAwake {
            return Status(icon: "moon.zzz", text: ko ? "대기 중 — \"Wake up Jarvis\" 또는 \"자비스, …\"라고 말씀하십시오" : "Asleep — say \"Wake up Jarvis\" or \"Jarvis, …\"", color: Holo.ice.opacity(0.6))
        }
        if !jarvis.lastHeard.isEmpty {
            return Status(icon: "ear", text: (ko ? "들은 말: " : "Heard: ") + jarvis.lastHeard, color: Holo.cyan.opacity(0.8))
        }
        return Status(icon: "waveform", text: ko ? "듣고 있습니다 — 그냥 말씀하시면 됩니다" : "Listening — just talk", color: Holo.cyan.opacity(0.8))
    }

    var body: some View {
        let st = status
        HStack(spacing: 6) {
            Image(systemName: st.icon).font(.system(size: 11, weight: .semibold))
            Text(st.text).font(Holo.mono(11)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if st.fixSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                let label: String = jarvis.currentLanguage == .korean ? "설정 열기" : "Open Settings"
                Link(label, destination: url)
                    .font(Holo.mono(11, .bold))
            }
        }
        .foregroundStyle(st.color)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Hold to talk: listens while held (no wake phrase, no waiting for silence), then carries out
/// what was said. The dependable way to speak when the room is noisy.
struct HoldToTalkButton: View {
    @Environment(JarvisController.self) private var jarvis
    @GestureState private var pressing = false

    var body: some View {
        let active: Bool = jarvis.pushToTalkActive
        let tint: Color = active ? Holo.green : Holo.cyan
        let fill: Color = tint.opacity(active ? 0.22 : 0.08)
        let edge: Color = tint.opacity(0.5)
        let icon: String = active ? "mic.circle.fill" : "mic.circle"
        let label: String = jarvis.currentLanguage == .korean ? "말하기" : "TALK"
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
            Text(label)
                .font(Holo.mono(8, .bold))
        }
        .foregroundStyle(tint)
        .frame(width: 52, height: 44)
        .background(RoundedRectangle(cornerRadius: 10).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(edge))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($pressing) { _, state, _ in state = true }
        )
        .onChange(of: pressing) { _, down in jarvis.pushToTalk(down) }
        .accessibilityLabel(jarvis.currentLanguage == .korean ? "누르고 있는 동안 말하기" : "Hold to talk")
        .accessibilityAddTraits(.isButton)
    }
}
