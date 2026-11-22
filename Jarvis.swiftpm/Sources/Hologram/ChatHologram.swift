import SwiftUI

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
            if !jarvis.partialTranscript.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "waveform").foregroundStyle(Holo.cyan)
                    Text(jarvis.partialTranscript)
                        .font(Holo.mono(12))
                        .foregroundStyle(Holo.ice.opacity(0.8))
                        .lineLimit(2)
                    Spacer()
                }
                .transition(.opacity)
            }
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
            TextField("", text: $draft, axis: .vertical)
                .font(Holo.mono(14))
                .foregroundStyle(.white)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border))
    }

    private var sendButton: some View {
        let empty: Bool = draft.isEmpty
        let blank: Bool = draft.trimmingCharacters(in: .whitespaces).isEmpty
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
            }
            if message.role != .user { Spacer(minLength: 40) }
        }
    }
}
