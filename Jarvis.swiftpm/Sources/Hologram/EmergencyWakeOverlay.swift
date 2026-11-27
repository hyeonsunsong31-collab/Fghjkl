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

    /// Size of the button's hosting view (the only part of the window that takes touches).
    static let buttonSide: CGFloat = 64

    func install(in scene: UIWindowScene, controller: JarvisController) {
        guard window == nil else { return }
        let w = PassthroughWindow(windowScene: scene)
        // Above every screen, sheet and panel of the app, but below alerts so iOS
        // permission and confirmation dialogs always stay on top and tappable.
        w.windowLevel = .normal + 1
        w.backgroundColor = .clear

        // A plain UIKit root view (it never takes touches) with the SwiftUI button hosted in a
        // small, fixed-size view at the bottom right. Hit-testing is decided by that view's frame:
        // since iOS 18, SwiftUI content no longer exposes separate UIViews per control, so the old
        // "pass through unless a subview was hit" test silently swallowed every tap on the button.
        let root = UIViewController()
        root.view.backgroundColor = .clear
        w.rootViewController = root
        let host = UIHostingController(rootView: EmergencyWakeButton().environment(controller))
        host.view.backgroundColor = .clear
        host.view.clipsToBounds = false
        host.safeAreaRegions = []
        root.addChild(host)
        root.view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        let side = Self.buttonSide
        NSLayoutConstraint.activate([
            host.view.widthAnchor.constraint(equalToConstant: side),
            host.view.heightAnchor.constraint(equalToConstant: side),
            host.view.trailingAnchor.constraint(equalTo: root.view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            host.view.bottomAnchor.constraint(equalTo: root.view.safeAreaLayoutGuide.bottomAnchor, constant: -116)
        ])
        host.didMove(toParent: root)
        w.touchTarget = host.view
        w.isHidden = false
        window = w
        // The hidden volume slider needs a window too.
        DeviceControls.installVolumeView(in: w)
        CrashLog.breadcrumb("emergency button installed")
    }
}

/// Window that only takes touches inside its button; everything else goes to the app below.
final class PassthroughWindow: UIWindow {
    weak var touchTarget: UIView?

    // Never steal keyboard focus from the main window (typing must keep working).
    override var canBecomeKey: Bool { false }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let target = touchTarget, !target.isHidden, target.window === self else { return false }
        return target.bounds.contains(target.convert(point, from: self))
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard self.point(inside: point, with: event) else { return nil }
        return super.hitTest(point, with: event)
    }
}

struct EmergencyWakeButton: View {
    @Environment(JarvisController.self) private var jarvis
    @State private var pulse = false

    var body: some View {
        // Fills exactly the small hosting view placed by `EmergencyWakeOverlay`.
        Button {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            jarvis.emergencyWake()
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
            .contentShape(Circle())
            .holoGlow(Holo.amber, radius: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Emergency wake · 비상 웨이크")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}
