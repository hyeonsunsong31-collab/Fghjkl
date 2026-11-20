import SwiftUI
import UIKit

/// The **emergency wake button** (requirement 9): a separate top-level window
/// above every screen, sheet and panel of the app, so it is always visible and
/// tappable while Jarvis runs. (Outside the app, iOS forbids overlays: the
/// AssistiveTouch shortcut and the PiP hologram take over — see the guide.)
@MainActor
final class EmergencyWakeOverlay {
    static let shared = EmergencyWakeOverlay()
    private var window: PassthroughWindow?

    func install(in scene: UIWindowScene, controller: JarvisController) {
        guard window == nil else { return }
        let w = PassthroughWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        let host = UIHostingController(rootView: EmergencyWakeButton().environment(controller))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = false
        window = w
        // The hidden volume slider needs a window too.
        DeviceControls.installVolumeView(in: w)
    }
}

/// Window that only intercepts touches on its interactive content.
final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        // Let touches on the transparent root fall through to the app below.
        return hit == rootViewController?.view ? nil : hit
    }
}

struct EmergencyWakeButton: View {
    @Environment(JarvisController.self) private var jarvis
    @State private var pulse = false

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    if jarvis.isAwake { jarvis.speech.stop(); jarvis.wake(source: .button, speak: false) } else { jarvis.wake(source: .button) }
                } label: {
                    ZStack {
                        Circle().fill(RadialGradient(colors: [Holo.amber.opacity(0.95), Holo.red.opacity(0.75)], center: .center, startRadius: 2, endRadius: 30))
                        Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
                        Circle().strokeBorder(Holo.amber, lineWidth: 2).scaleEffect(pulse ? 1.45 : 1).opacity(pulse ? 0 : 0.9)
                        Image(systemName: jarvis.isAwake ? "waveform.circle.fill" : "power")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 58, height: 58)
                    .holoGlow(Holo.amber, radius: 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Emergency wake · 비상 웨이크")
                .padding(.trailing, 18)
                .padding(.bottom, 120)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}
