import SwiftUI
import UIKit

@main
struct JarvisApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var jarvis = JarvisController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(jarvis)
                .background(WindowSceneReader { scene in
                    EmergencyWakeOverlay.shared.install(in: scene, controller: jarvis)
                })
                .onOpenURL { url in handle(url) }
                .onAppear { jarvis.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                jarvis.start()
            case .background:
                jarvis.saveBrain()
                jarvis.scene.save()
            default:
                break
            }
        }
    }

    /// jarvis://wake · jarvis://ask?text=… · jarvis://open3d · jarvis://bridge?status=…
    private func handle(_ url: URL) {
        guard url.scheme == "jarvis" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch url.host {
        case "wake":
            jarvis.wake(source: .shortcut)
        case "ask":
            if let text = items.first(where: { $0.name == "text" })?.value, !text.isEmpty {
                jarvis.submit(text, modality: .shortcut)
            } else {
                jarvis.wake(source: .shortcut)
            }
        case "open3d":
            jarvis.wake(source: .shortcut, speak: false)
            jarvis.setSpaceOpen(true)
        case "sleep":
            jarvis.sleep()
        case "bridge":
            let status = items.first(where: { $0.name == "status" })?.value ?? "success"
            jarvis.statusNote = "Jarvis Bridge: \(status)"
        default:
            jarvis.wake(source: .shortcut)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        CrashLog.install()
        CrashLog.breadcrumb("launch")
        BackgroundTasks.register()
        UIDevice.current.isBatteryMonitoringEnabled = true
        return true
    }
}

/// Gives access to the hosting `UIWindowScene` (needed for the always-on-top wake button window).
struct WindowSceneReader: UIViewRepresentable {
    let onScene: (UIWindowScene) -> Void

    func makeUIView(context: Context) -> SceneProbeView {
        let v = SceneProbeView()
        v.onScene = onScene
        return v
    }

    func updateUIView(_ uiView: SceneProbeView, context: Context) {}

    final class SceneProbeView: UIView {
        var onScene: ((UIWindowScene) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene {
                let callback = onScene
                DispatchQueue.main.async { callback?(scene) }
            }
        }
    }
}
