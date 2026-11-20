import SwiftUI
import RealityKit
import UIKit

/// Full-screen 3D project space (the holographic workshop that replaces the
/// wallpaper while open). Supports:
/// - left-click / finger drag on an object → move it (screen-plane drag)
/// - drag on empty space → orbit; two-finger drag → pan
/// - mouse scroll wheel while pointing at an object → scale that object
///   (on empty space → zoom the camera)
/// - pinch → scale the touched/selected object (or zoom); rotate → spin it
/// - tap → select; double-tap → focus; right-click → clone/delete menu
struct ProjectSpaceView: UIViewRepresentable {
    let scene: SceneController
    var onContextAction: ((String, String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(scene: scene, onContextAction: onContextAction) }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.renderOptions.insert(.disableMotionBlur)
        scene.attach(view)
        context.coordinator.install(on: view)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate {
        let scene: SceneController
        let onContextAction: ((String, String) -> Void)?
        private var lastPan: CGPoint = .zero
        private var lastTwoFinger: CGPoint = .zero
        private var pinchTarget: String?
        private var rotateTarget: String?
        private var lastRotation: CGFloat = 0
        private var hoverPoint: CGPoint?

        init(scene: SceneController, onContextAction: ((String, String) -> Void)?) {
            self.scene = scene
            self.onContextAction = onContextAction
        }

        func install(on view: ARView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            view.addGestureRecognizer(pan)

            let twoFinger = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
            twoFinger.minimumNumberOfTouches = 2
            twoFinger.delegate = self
            view.addGestureRecognizer(twoFinger)

            // Mouse / trackpad scroll wheel (no touches).
            let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
            scroll.allowedScrollTypesMask = .all
            scroll.allowedTouchTypes = []
            scroll.delegate = self
            view.addGestureRecognizer(scroll)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)

            let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
            rotate.delegate = self
            view.addGestureRecognizer(rotate)

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            view.addGestureRecognizer(doubleTap)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.require(toFail: doubleTap)
            view.addGestureRecognizer(tap)

            let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
            view.addGestureRecognizer(hover)

            view.addInteraction(UIContextMenuInteraction(delegate: self))
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            (g is UIPinchGestureRecognizer || g is UIRotationGestureRecognizer || g.numberOfTouches >= 2)
                && (other is UIPinchGestureRecognizer || other is UIRotationGestureRecognizer || other.numberOfTouches >= 2)
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            let p = g.location(in: g.view)
            switch g.state {
            case .began:
                lastPan = p
                if !scene.beginDrag(at: p) { lastPan = p }
            case .changed:
                if scene.isDragging {
                    scene.drag(to: p)
                } else {
                    scene.orbit(dx: Float(p.x - lastPan.x), dy: Float(p.y - lastPan.y))
                }
                lastPan = p
            default:
                scene.endDrag()
            }
        }

        @objc func handleTwoFingerPan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            switch g.state {
            case .began: lastTwoFinger = t
            case .changed:
                scene.panCamera(dx: Float(t.x - lastTwoFinger.x), dy: Float(t.y - lastTwoFinger.y))
                lastTwoFinger = t
            default: break
            }
        }

        @objc func handleScroll(_ g: UIPanGestureRecognizer) {
            guard g.state == .changed || g.state == .began else { return }
            let t = g.translation(in: g.view)
            g.setTranslation(.zero, in: g.view)
            let factor = Float(exp(Double(-t.y) * 0.004))
            let point = hoverPoint ?? g.location(in: g.view)
            if let id = scene.objectID(at: point) {
                scene.scaleObject(id: id, by: factor)
            } else {
                scene.zoomCamera(factor)
            }
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began:
                pinchTarget = scene.objectID(at: g.location(in: g.view)) ?? scene.document.selectedID
            case .changed:
                let factor = Float(g.scale)
                g.scale = 1
                if let id = pinchTarget { scene.scaleObject(id: id, by: factor) } else { scene.zoomCamera(factor) }
            default:
                pinchTarget = nil
            }
        }

        @objc func handleRotate(_ g: UIRotationGestureRecognizer) {
            switch g.state {
            case .began:
                rotateTarget = scene.objectID(at: g.location(in: g.view)) ?? scene.document.selectedID
                lastRotation = 0
            case .changed:
                if let id = rotateTarget {
                    scene.rotateObject(id: id, byDegrees: -Float(g.rotation - lastRotation) * 180 / .pi)
                }
                lastRotation = g.rotation
            default:
                rotateTarget = nil
            }
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            scene.select(id: scene.objectID(at: g.location(in: g.view)))
        }

        @objc func handleDoubleTap(_ g: UITapGestureRecognizer) {
            if let id = scene.objectID(at: g.location(in: g.view)), let obj = scene.document.objects.first(where: { $0.id == id }) {
                scene.target = obj.position + SIMD3(0, obj.size.y * obj.scale.y * 0.3, 0)
                scene.distance = max(0.5, obj.footprint * 6)
                scene.updateCamera()
            } else {
                scene.resetCamera()
            }
        }

        @objc func handleHover(_ g: UIHoverGestureRecognizer) {
            switch g.state {
            case .began, .changed:
                hoverPoint = g.location(in: g.view)
                scene.hover(at: hoverPoint)
            default:
                hoverPoint = nil
                scene.hover(at: nil)
            }
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            guard let id = scene.objectID(at: location) else { return nil }
            scene.select(id: id)
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                let clone = UIAction(title: "Clone · 복제", image: UIImage(systemName: "plus.square.on.square")) { _ in self?.onContextAction?("clone", id) }
                let delete = UIAction(title: "Delete · 삭제", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in self?.onContextAction?("delete", id) }
                let colors = ["red", "orange", "yellow", "green", "cyan", "blue", "purple", "gold", "white"].map { c in
                    UIAction(title: c.capitalized) { _ in self?.onContextAction?("color:\(c)", id) }
                }
                return UIMenu(title: "", children: [clone, delete, UIMenu(title: "Colour · 색상", children: colors)])
            }
        }
    }
}
