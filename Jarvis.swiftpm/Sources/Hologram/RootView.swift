import SwiftUI

/// The holographic HUD. When the 3D project space is open it becomes the
/// full-screen background (the workshop replaces the wallpaper), and every
/// panel floats above it.
struct RootView: View {
    @Environment(JarvisController.self) private var jarvis
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 760
            ZStack {
                // Background: 3D workshop or animated hex field.
                if jarvis.spaceOpen {
                    ProjectSpaceView(scene: jarvis.scene) { action, id in contextAction(action, id) }
                        .ignoresSafeArea()
                        .transition(.opacity)
                    if jarvis.handTrackingEnabled { HandOverlay().ignoresSafeArea() }
                } else {
                    HexBackdrop()
                }
                Scanlines().ignoresSafeArea()

                VStack(spacing: 10) {
                    StatusBar()
                    if jarvis.spaceOpen {
                        HStack(alignment: .top, spacing: 10) {
                            Spacer(minLength: 0)
                            if wide {
                                CommandDeck().frame(width: 300).frame(maxHeight: geo.size.height * 0.62)
                            }
                        }
                    } else {
                        Spacer(minLength: 0)
                        ArcCore(phase: jarvis.phase, level: jarvis.phase == .speaking ? 0.6 : jarvis.inputLevel,
                                size: min(geo.size.width, geo.size.height) * (wide ? 0.34 : 0.5))
                            .onTapGesture { jarvis.isAwake ? jarvis.sleep() : jarvis.wake(source: .button) }
                        if !jarvis.isAwake {
                            Text(jarvis.currentLanguage == .korean ? "\"Wake up Jarvis\" 라고 말씀하시거나 비상 웨이크 버튼을 누르십시오"
                                                                   : "Say \"Wake up Jarvis\" or press the emergency wake button")
                                .font(Holo.mono(12)).foregroundStyle(Holo.ice.opacity(0.7)).multilineTextAlignment(.center)
                                // Hidden (layout kept) while the onboarding card sits on top of it.
                                .opacity(jarvis.activePanel == .onboarding ? 0 : 1)
                        } else {
                            HoloWaveform(level: jarvis.inputLevel, color: Holo.phaseColor(jarvis.phase)).frame(width: 220, height: 28)
                        }
                        Spacer(minLength: 0)
                    }
                    bottomArea(wide: wide, height: geo.size.height)
                }
                .padding(.horizontal, wide ? 18 : 10)
                .padding(.vertical, 8)

                // Side panels.
                if let panel = jarvis.activePanel {
                    panelView(panel)
                        .frame(maxWidth: panel == .onboarding ? 560 : (wide ? min(640, geo.size.width * 0.55) : .infinity),
                               maxHeight: panel == .onboarding ? 620 : geo.size.height * 0.82)
                        .padding(wide ? 24 : 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: panel == .onboarding ? .center : .leading)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(5)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Holo.cyan)
    }

    @ViewBuilder
    private func bottomArea(wide: Bool, height: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                TurnCards().frame(maxHeight: height * 0.3, alignment: .bottom)
                ChatHologram(compact: jarvis.spaceOpen && !wide)
            }
            .frame(maxWidth: wide ? 640 : .infinity)
            if wide {
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 8) {
                    MiniPlayer()
                    PresenceTile().frame(width: 160, height: 90)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if !wide { MiniPlayer().offset(y: -70) }
        }
        .overlay(alignment: .bottomLeading) {
            if jarvis.spaceOpen && !wide {
                CommandDeck().frame(height: 220).offset(y: -260)
            }
        }
    }

    @ViewBuilder
    private func panelView(_ panel: Panel) -> some View {
        switch panel {
        case .history: HistoryPanel()
        case .brain: BrainPanel()
        case .settings: SettingsPanel()
        case .browser: BrowserPanel()
        case .help: HelpPanel()
        case .onboarding: OnboardingPanel()
        }
    }

    private func contextAction(_ action: String, _ id: String) {
        jarvis.scene.select(id: id)
        if action == "clone" { jarvis.submit(jarvis.currentLanguage == .korean ? "복제해" : "clone it", modality: .button) }
        else if action == "delete" { jarvis.submit(jarvis.currentLanguage == .korean ? "삭제해" : "delete it", modality: .button) }
        else if action.hasPrefix("color:") { jarvis.scene.recolor(["target": "current"], color: String(action.dropFirst(6))) }
    }
}
