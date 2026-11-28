import SwiftUI
import UIKit

/// The holographic HUD. When the 3D project space is open it becomes the
/// full-screen background (the workshop replaces the wallpaper), and every
/// panel floats above it.
struct RootView: View {
    @Environment(JarvisController.self) private var jarvis
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 760
            ZStack {
                // Background: 3D workshop or animated hex field.
                if jarvis.spaceOpen {
                    ProjectSpaceView(scene: jarvis.scene) { action, id in contextAction(action, id) }
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onAppear {
                            jarvis.scene.framingInsets = Self.hudInsets(geo.size)
                            jarvis.scene.frameAll(animated: false)
                        }
                        .onChange(of: geo.size) { _, size in jarvis.scene.framingInsets = Self.hudInsets(size) }
                    if jarvis.handTrackingEnabled { HandOverlay().ignoresSafeArea() }
                } else {
                    // Decoration pauses while typing so the keyboard always gets the main thread.
                    HexBackdrop(paused: jarvis.typing)
                }
                Scanlines(paused: jarvis.typing).ignoresSafeArea()

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
                        // Tap: wake up / listen afresh (never sleep). Long press: go to sleep.
                        LiveArcCore(size: min(geo.size.width, geo.size.height) * (wide ? 0.34 : 0.5))
                            .onLongPressGesture(minimumDuration: 0.8) { jarvis.sleep() }
                            .onTapGesture { jarvis.coreTapped() }
                        if !jarvis.isAwake {
                            Text(jarvis.currentLanguage == .korean ? "\"Wake up Jarvis\" 라고 말씀하시거나 비상 웨이크 버튼을 누르십시오"
                                                                   : "Say \"Wake up Jarvis\" or press the emergency wake button")
                                .font(Holo.mono(12)).foregroundStyle(Holo.ice.opacity(0.7)).multilineTextAlignment(.center)
                                // Hidden (layout kept) while the onboarding card sits on top of it.
                                .opacity(jarvis.activePanel == .onboarding ? 0 : 1)
                        } else {
                            LiveWaveform().frame(width: 220, height: 28)
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
                        .frame(maxWidth: panelWidth(panel, wide: wide, width: geo.size.width),
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
        // SwiftUI's own URL opener is the most reliable route out of a Swift Playground-hosted app.
        .onAppear { URLOpener.swiftUIOpen = openURL }
    }

    /// Screen area the HUD covers while the 3D space is open (status bar, command deck,
    /// option cards and chat), so new objects are framed where they stay visible.
    static func hudInsets(_ size: CGSize) -> UIEdgeInsets {
        let wide = size.width > 760
        return UIEdgeInsets(top: 64, left: 0,
                            bottom: size.height * (wide ? 0.33 : 0.52),
                            right: wide ? 336 : 0)
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

    private func panelWidth(_ panel: Panel, wide: Bool, width: CGFloat) -> CGFloat {
        if panel == .onboarding { return 560 }
        if !wide { return .infinity }
        let share: CGFloat = panel == .studio ? 0.7 : 0.55
        let cap: CGFloat = panel == .studio ? 900 : 640
        return min(cap, width * share)
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
        case .studio: StudioPanel()
        }
    }

    private func contextAction(_ action: String, _ id: String) {
        jarvis.scene.select(id: id)
        if action == "clone" { jarvis.submit(jarvis.currentLanguage == .korean ? "복제해" : "clone it", modality: .button) }
        else if action == "delete" { jarvis.submit(jarvis.currentLanguage == .korean ? "삭제해" : "delete it", modality: .button) }
        else if action.hasPrefix("color:") { jarvis.scene.recolor(["target": "current"], color: String(action.dropFirst(6))) }
    }
}
