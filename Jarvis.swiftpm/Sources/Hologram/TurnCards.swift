import SwiftUI

/// Cards for the last turn: time estimate, explanations by purpose (error /
/// answer / process), adjustment options (tap = execute) and recommendations,
/// plus live workflow progress.
struct TurnCards: View {
    @Environment(JarvisController.self) private var jarvis

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let wf = jarvis.currentWorkflow {
                WorkflowCard(workflow: wf)
            }
            if let turn = jarvis.lastTurn {
                ForEach(Array(turn.explanations.enumerated()), id: \.offset) { _, e in
                    ExplanationCard(explanation: e, language: turn.language)
                }
                if !turn.options.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HUDLabel(text: turn.language == .korean ? "조정 옵션" : "Adjustments", color: Holo.cyan, size: 9)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(turn.options) { option in
                                    Button { jarvis.choose(option) } label: {
                                        Text(option.label)
                                            .font(Holo.mono(12, .semibold))
                                            .foregroundStyle(Holo.cyan)
                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(Capsule().fill(Holo.cyan.opacity(0.12)))
                                            .overlay(Capsule().strokeBorder(Holo.cyan.opacity(0.6)))
                                    }
                                    .buttonStyle(.plain)
                                    .hoverEffect(.lift)
                                }
                            }
                        }
                    }
                }
                ForEach(turn.recommendations) { r in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.max.fill").foregroundStyle(Holo.amber)
                        Text(r.text).font(.system(size: 13, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                        Spacer(minLength: 0)
                        if let u = r.utterance {
                            Button(turn.language == .korean ? "적용" : "Apply") { jarvis.submit(u, modality: .button) }
                                .font(Holo.mono(11, .bold))
                                .foregroundStyle(Holo.amber)
                        }
                    }
                    .padding(10)
                    .holoPanel(corner: 10, tint: Holo.amber)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: jarvis.lastTurn?.reply)
    }
}

struct ExplanationCard: View {
    let explanation: Explanation
    let language: DetectedLanguage
    @State private var expanded = false

    private var meta: (String, String, Color) {
        switch explanation.kind {
        case .error: return ("exclamationmark.triangle.fill", language == .korean ? "오류 설명" : "Error", Holo.red)
        case .answer: return ("text.bubble.fill", language == .korean ? "답변" : "Answer", Holo.cyan)
        case .process: return ("list.bullet.rectangle.portrait.fill", language == .korean ? "진행 과정" : "Process", Holo.green)
        case .timeEstimate: return ("timer", language == .korean ? "예상 소요 시간" : "Time estimate", Holo.amber)
        }
    }

    var body: some View {
        let (icon, title, color) = meta
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                HUDLabel(text: title, color: color, size: 9)
                Spacer()
                if explanation.text.count > 120 {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(color.opacity(0.8)).font(.caption)
                }
            }
            Text(explanation.text)
                .font(.system(size: 12.5, design: explanation.kind == .process ? .monospaced : .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(expanded ? nil : 3)
                .textSelection(.enabled)
        }
        .padding(10)
        .holoPanel(corner: 10, tint: color)
        .onTapGesture { withAnimation { expanded.toggle() } }
    }
}

struct WorkflowCard: View {
    let workflow: Workflow
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HUDLabel(text: workflow.language == .korean ? "작업 진행" : "Workflow", color: Holo.green, size: 9)
                Spacer()
                Text("\(Int(workflow.progress * 100))%").font(Holo.mono(11, .bold)).foregroundStyle(Holo.green)
            }
            ProgressView(value: workflow.progress).tint(Holo.green)
            Text(workflow.narration(workflow.language)).font(Holo.mono(11)).foregroundStyle(.white.opacity(0.85))
        }
        .padding(10)
        .holoPanel(corner: 10, tint: Holo.green)
    }
}
