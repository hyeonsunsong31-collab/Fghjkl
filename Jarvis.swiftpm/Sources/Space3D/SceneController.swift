import Foundation
import RealityKit
import UIKit
import ModelIO
import Observation

/// Owns the 3D project document and mirrors it into RealityKit entities.
/// Every manipulation (voice, text, buttons, mouse, touch, hand gestures)
/// goes through here, so all of them share undo/redo and persistence.
@MainActor
@Observable
final class SceneController {
    var document = SceneDocument()
    var hoveredID: String?
    /// Hand-tracking reticle in view coordinates (nil when no hand is seen).
    var reticle: CGPoint?
    var reticlePinching = false
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    @ObservationIgnored weak var arView: ARView?
    @ObservationIgnored private let root = AnchorEntity(world: .zero)
    @ObservationIgnored private let cameraAnchor = AnchorEntity(world: .zero)
    @ObservationIgnored private let camera = PerspectiveCamera()
    @ObservationIgnored private var entities: [String: Entity] = [:]
    @ObservationIgnored private var meshCache: [String: MeshResource] = [:]
    @ObservationIgnored private var undoStack: [SceneDocument] = []
    @ObservationIgnored private var redoStack: [SceneDocument] = []
    @ObservationIgnored private var dragState: (id: String, planePoint: SIMD3<Float>, normal: SIMD3<Float>, offset: SIMD3<Float>)?
    @ObservationIgnored private var gestureScaleStart: (id: String, scale: SIMD3<Float>, rotation: SIMD3<Float>)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var cameraAnimation: AnimationPlaybackController?

    // Orbit camera.
    var azimuth: Float = 0
    var elevation: Float = 0.38
    var distance: Float = 1.7
    var target = SIMD3<Float>(0, 0.22, -0.05)

    init() { load() }

    // MARK: View attachment

    func attach(_ view: ARView) {
        arView = view
        view.environment.background = .color(HoloPalette.background)
        if root.parent == nil {
            view.scene.addAnchor(root)
            view.scene.addAnchor(cameraAnchor)
            cameraAnchor.addChild(camera)
            camera.camera.fieldOfViewInDegrees = 50
            addLighting()
            addGrid()
        }
        updateCamera()
        rebuildAll()
        frameAll(animated: false)
    }

    private func addLighting() {
        let key = DirectionalLight()
        key.light.intensity = 2200
        key.light.color = UIColor(red: 0.75, green: 0.92, blue: 1, alpha: 1)
        key.look(at: .zero, from: SIMD3(0.8, 1.6, 1.2), relativeTo: nil)
        root.addChild(key)
        let fill = PointLight()
        fill.light.intensity = 9000
        fill.light.color = UIColor(red: 0, green: 0.85, blue: 1, alpha: 1)
        fill.light.attenuationRadius = 4
        fill.position = SIMD3(-0.8, 0.6, 0.6)
        root.addChild(fill)
        // Neutral front fill so painted and metal parts keep their true colours.
        let front = DirectionalLight()
        front.light.intensity = 1100
        front.light.color = .white
        front.look(at: SIMD3(0, 0.2, 0), from: SIMD3(-0.6, 0.5, 1.6), relativeTo: nil)
        root.addChild(front)
    }

    private func addGrid() {
        // Wide enough to fill the view when the camera backs off to frame many objects;
        // lines fade towards the edges (a few shared materials, one per fade level).
        let extent: Float = 4.0
        let step: Float = 0.1
        let fadeLevels = 8
        let materials = (0..<fadeLevels).map { level in
            HoloMaterials.line(HoloPalette.grid, opacity: 0.35 * (1 - Float(level) / Float(fadeLevels)))
        }
        let thin = MeshResource.generateBox(size: SIMD3(extent * 2, 0.0015, 0.0015))
        let thinZ = MeshResource.generateBox(size: SIMD3(0.0015, 0.0015, extent * 2))
        let lines = Int((extent / step).rounded())
        for i in -lines...lines {
            let k = Float(i) * step
            let level = min(fadeLevels - 1, Int(abs(k) / extent * Float(fadeLevels)))
            let lx = ModelEntity(mesh: thin, materials: [materials[level]])
            lx.position = SIMD3(0, 0, k)
            root.addChild(lx)
            let lz = ModelEntity(mesh: thinZ, materials: [materials[level]])
            lz.position = SIMD3(k, 0, 0)
            root.addChild(lz)
        }
        // Holographic emitter ring under the workspace.
        let ringMesh = try? MeshResource.generate(from: [Self.descriptor(MeshGenerator.torus(majorRadius: 0.55, minorRadius: 0.004, segments: 96, sides: 6), name: "ring")])
        if let ringMesh {
            let ring = ModelEntity(mesh: ringMesh, materials: [HoloMaterials.line(HoloPalette.uiColor("cyan"), opacity: 0.8)])
            ring.position = SIMD3(0, 0.001, -0.05)
            root.addChild(ring)
        }
    }

    // MARK: Camera

    func updateCamera(animated: Bool = false) {
        let e = max(-0.2, min(1.45, elevation))
        let d = max(0.35, min(6, distance))
        let offset = SIMD3<Float>(d * cos(e) * sin(azimuth), d * sin(e), d * cos(e) * cos(azimuth))
        // Any direct manipulation (orbit, pan, zoom) takes over from a running glide.
        cameraAnimation?.stop()
        cameraAnimation = nil
        if animated {
            let probe = Entity()
            probe.look(at: target, from: target + offset, relativeTo: nil)
            cameraAnimation = camera.move(to: probe.transform, relativeTo: nil, duration: 0.6, timingFunction: .easeInOut)
        } else {
            camera.look(at: target, from: target + offset, relativeTo: nil)
        }
    }

    /// Screen area (points) covered by the HUD over the 3D view — status bar, command
    /// deck, chat hologram — so framing centres objects in the part that stays visible.
    @ObservationIgnored var framingInsets = UIEdgeInsets.zero

    /// Keeps every object in view after commands add or clone objects: re-aims at the
    /// group so it sits in the uncovered part of the screen and backs the camera off just
    /// enough to fit it (never zooms in on the user).
    func frameAll(animated: Bool = true) {
        let objs = document.objects
        guard !objs.isEmpty else { return }
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for o in objs {
            let half = o.size * o.scale / 2
            // Composite models stand on their origin; primitives are centred on it.
            let centre = o.isComposite ? SIMD3<Float>(o.position.x, o.position.y + half.y, o.position.z) : o.position
            lo = simd_min(lo, centre - half)
            hi = simd_max(hi, centre + half)
        }
        let centre = (lo + hi) / 2
        let radius = max(0.2, simd_length(hi - lo) / 2)

        // Visible (uncovered) part of the view, as fractions and an offset in NDC.
        var bounds = arView?.bounds ?? .zero
        if bounds.width < 1 || bounds.height < 1 { bounds = CGRect(x: 0, y: 0, width: 1032, height: 1376) }
        let w = bounds.width, h = bounds.height
        let insets = framingInsets
        let freeW = max(w * 0.35, w - insets.left - insets.right)
        let freeH = max(h * 0.35, h - insets.top - insets.bottom)
        let cx = Float((insets.left + freeW / 2 - w / 2) / (w / 2))
        let cy = Float((insets.top + freeH / 2 - h / 2) / (h / 2))
        let tanV = tan(camera.camera.fieldOfViewInDegrees * Float.pi / 360) // vertical field of view
        let tanH = tanV * Float(w / h)
        let fitAngle = min(atan(tanH * Float(freeW / w)), atan(tanV * Float(freeH / h)))
        distance = max(distance, min(6, radius / sin(fitAngle) * 1.1))

        // Shift the aim point so the group's centre projects onto the visible area's centre.
        let d = max(0.35, min(6, distance))
        let e = max(-0.2, min(1.45, elevation))
        let forward = -SIMD3<Float>(cos(e) * sin(azimuth), sin(e), cos(e) * cos(azimuth))
        let right = SIMD3<Float>(cos(azimuth), 0, -sin(azimuth))
        let up = simd_cross(right, forward)
        target = centre - right * (cx * d * tanH) + up * (cy * d * tanV)
        updateCamera(animated: animated && arView != nil)
    }

    func orbit(dx: Float, dy: Float) {
        azimuth -= dx * 0.008
        elevation += dy * 0.006
        updateCamera()
    }

    func zoomCamera(_ factor: Float) {
        distance /= max(0.2, factor)
        distance = max(0.35, min(6, distance))
        updateCamera()
    }

    func panCamera(dx: Float, dy: Float) {
        let scale: Float = 0.0015 * distance
        let right = SIMD3<Float>(cos(azimuth), 0, -sin(azimuth))
        let sideways: SIMD3<Float> = right * (-dx * scale)
        let upwards = SIMD3<Float>(0, dy * scale, 0)
        target += sideways + upwards
        updateCamera()
    }

    func resetCamera() {
        azimuth = 0; elevation = 0.38; distance = 1.7; target = SIMD3(0, 0.22, -0.05)
        updateCamera()
    }

    private var cameraPosition: SIMD3<Float> { camera.position(relativeTo: nil) }

    // MARK: Entity sync

    static func descriptor(_ m: MeshData, name: String) -> MeshDescriptor {
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(m.positions)
        d.normals = MeshBuffers.Normals(m.normals)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(m.uvs)
        d.primitives = .triangles(m.indices)
        return d
    }

    private func mesh(for obj: SceneObject) -> MeshResource? {
        if obj.shape == "text" {
            return MeshResource.generateText(obj.text ?? "Jarvis", extrusionDepth: 0.012,
                                             font: .systemFont(ofSize: 0.07, weight: .semibold),
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byWordWrapping)
        }
        let param: Float = obj.param ?? 0
        let key = "\(obj.shape)-\(obj.size.x)-\(obj.size.y)-\(obj.size.z)-\(param)"
        if let cached = meshCache[key] { return cached }
        let data = MeshGenerator.mesh(for: obj.shape, size: obj.size, param: param, segments: 40)
        let resource = try? MeshResource.generate(from: [Self.descriptor(data, name: obj.shape)])
        if let resource { meshCache[key] = resource }
        return resource
    }

    private func makeEntity(_ obj: SceneObject) -> Entity {
        let selected = obj.id == document.selectedID
        let hovered = obj.id == hoveredID
        let entity: Entity
        if let parts = obj.parts, !parts.isEmpty {
            let group = Entity()
            let solid = renderStyle.solid(composite: true)
            for part in parts {
                guard let m = mesh(for: part) else { continue }
                let material = HoloMaterials.part(HoloPalette.uiColor(part.color), material: part.material, solid: solid,
                                                  selected: selected, hovered: hovered)
                let child = ModelEntity(mesh: m, materials: [material])
                child.position = part.position
                child.orientation = Self.quaternion(part.rotation)
                child.scale = part.scale
                group.addChild(child)
            }
            entity = group
        } else if let m = mesh(for: obj) {
            let material = HoloMaterials.part(HoloPalette.uiColor(obj.color), material: obj.material ?? "plastic",
                                              solid: renderStyle.solid(composite: false), selected: selected, hovered: hovered)
            entity = ModelEntity(mesh: m, materials: [material])
        } else {
            entity = Entity()
        }
        entity.name = obj.id
        apply(obj, to: entity)
        entity.generateCollisionShapes(recursive: true)
        return entity
    }

    private func apply(_ obj: SceneObject, to entity: Entity) {
        entity.position = obj.position
        entity.orientation = Self.quaternion(obj.rotation)
        entity.scale = obj.scale
    }

    static func quaternion(_ degrees: SIMD3<Float>) -> simd_quatf {
        let r = degrees * (Float.pi / 180)
        return simd_quatf(angle: r.y, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: r.x, axis: SIMD3(1, 0, 0)) * simd_quatf(angle: r.z, axis: SIMD3(0, 0, 1))
    }

    func rebuildAll() {
        for e in entities.values { e.removeFromParent() }
        entities.removeAll()
        for obj in document.objects {
            let e = makeEntity(obj)
            root.addChild(e)
            entities[obj.id] = e
        }
    }

    /// Re-create entities whose appearance changed; update transforms of the rest.
    private func sync(rebuild ids: Set<String> = []) {
        let live = Set(document.objects.map(\.id))
        for (id, e) in entities where !live.contains(id) {
            e.removeFromParent()
            entities[id] = nil
        }
        for obj in document.objects {
            if let e = entities[obj.id], !ids.contains(obj.id) {
                apply(obj, to: e)
            } else {
                entities[obj.id]?.removeFromParent()
                let e = makeEntity(obj)
                root.addChild(e)
                entities[obj.id] = e
            }
        }
        scheduleSave()
    }

    private func refreshHighlight(_ ids: [String?]) {
        sync(rebuild: Set(ids.compactMap { $0 }))
    }

    // MARK: Undo / redo

    private func checkpoint() {
        undoStack.append(document)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(document)
        document = previous
        rebuildAll()
        scheduleSave()
        return true
    }

    func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(document)
        document = next
        rebuildAll()
        scheduleSave()
        return true
    }

    // MARK: Commands

    @discardableResult
    func create(shape: String, color: String?, count: Int, sizeFactor: Float = 1, text: String? = nil) -> [SceneObject] {
        checkpoint()
        var created: [SceneObject] = []
        let size = MeshGenerator.defaultSize(for: shape) * sizeFactor
        for _ in 0..<max(1, min(count, 30)) {
            created.append(document.add(shape: shape, color: color ?? "cyan", size: size, text: text))
        }
        rebuildAll()
        frameAll()
        scheduleSave()
        return created
    }

    @discardableResult
    func createComposite(_ spec: ModelSpec, color: String? = nil, design: String? = nil) -> SceneObject {
        checkpoint()
        let obj = document.addComposite(spec, color: color, design: design)
        rebuildAll()
        frameAll()
        scheduleSave()
        return obj
    }

    /// The designed model a follow-up refers to: the selected design, else the most recent one.
    func designTarget() -> SceneObject? {
        if let selected = document.selected, selected.design != nil { return selected }
        return document.objects.last { $0.design != nil }
    }

    /// Replace a design with its refined version where it stands (undoable).
    func refineDesign(_ id: String, spec: ModelSpec, design: String?) {
        checkpoint()
        document.replaceDesign(id, with: spec, design: design)
        document.selectedID = id
        sync(rebuild: [id])
        frameAll()
    }

    /// Real materials or holograms (see `RenderStyle`).
    var renderStyle: RenderStyle = RenderStyle.current

    func setRenderStyle(_ style: RenderStyle) {
        renderStyle = style
        RenderStyle.current = style
        rebuildAll()
    }

    @discardableResult
    func clone(_ params: [String: String], count: Int) -> [SceneObject] {
        let ids = document.resolve(params)
        guard !ids.isEmpty else { return [] }
        checkpoint()
        let created = document.clone(ids, count: count)
        rebuildAll()
        frameAll()
        scheduleSave()
        return created
    }

    @discardableResult
    func delete(_ params: [String: String]) -> Int {
        let ids = document.resolve(params)
        guard !ids.isEmpty else { return 0 }
        checkpoint()
        document.delete(ids)
        sync()
        return ids.count
    }

    func clear() {
        checkpoint()
        document.clear()
        sync()
    }

    @discardableResult
    func select(_ params: [String: String]) -> Bool {
        guard let id = document.resolve(params).first else { return false }
        let old = document.selectedID
        document.selectedID = id
        refreshHighlight([old, id])
        return true
    }

    func select(id: String?) {
        let old = document.selectedID
        document.selectedID = id
        refreshHighlight([old, id])
    }

    /// Move in camera-relative directions.
    @discardableResult
    func move(_ params: [String: String], direction: String, amount: Float) -> Bool {
        let ids = document.resolve(params)
        guard !ids.isEmpty else { return false }
        checkpoint()
        let right = SIMD3<Float>(cos(azimuth), 0, -sin(azimuth))
        let forward = SIMD3<Float>(-sin(azimuth), 0, -cos(azimuth))
        let delta: SIMD3<Float>
        switch direction {
        case "left": delta = -right * amount
        case "right": delta = right * amount
        case "up": delta = SIMD3(0, amount, 0)
        case "down": delta = SIMD3(0, -amount, 0)
        case "forward": delta = -forward * amount
        default: delta = forward * amount
        }
        for id in ids { document.update(id) { $0.position += delta } }
        sync()
        return true
    }

    @discardableResult
    func scale(_ params: [String: String], factor: Float) -> Bool {
        let ids = document.resolve(params)
        guard !ids.isEmpty else { return false }
        checkpoint()
        for id in ids {
            document.update(id) { obj in
                obj.scale = simd_clamp(obj.scale * factor, SIMD3(repeating: 0.05), SIMD3(repeating: 12))
                if obj.shape != "group" { obj.position.y = max(obj.position.y, obj.size.y * obj.scale.y / 2) }
            }
        }
        sync()
        return true
    }

    @discardableResult
    func rotate(_ params: [String: String], degrees: Float, axis: String) -> Bool {
        let ids = document.resolve(params)
        guard !ids.isEmpty else { return false }
        checkpoint()
        for id in ids {
            document.update(id) { obj in
                switch axis {
                case "x": obj.rotation.x += degrees
                case "z": obj.rotation.z += degrees
                default: obj.rotation.y += degrees
                }
            }
        }
        sync()
        return true
    }

    @discardableResult
    func recolor(_ params: [String: String], color: String) -> Bool {
        let ids = document.resolve(params)
        guard !ids.isEmpty else { return false }
        checkpoint()
        for id in ids {
            document.update(id) { obj in
                obj.color = color
                obj.parts = obj.parts?.map { var p = $0; p.color = color; return p }
            }
        }
        sync(rebuild: Set(ids))
        return true
    }

    // MARK: Pointer / touch / hand interaction

    func objectID(at point: CGPoint) -> String? {
        guard let view = arView, var entity = view.entity(at: point) else { return nil }
        while true {
            if entities[entity.name] != nil { return entity.name }
            guard let parent = entity.parent else { return nil }
            entity = parent
        }
    }

    func hover(at point: CGPoint?) {
        let id = point.flatMap { objectID(at: $0) }
        guard id != hoveredID else { return }
        let old = hoveredID
        hoveredID = id
        refreshHighlight([old, id])
    }

    /// Begin dragging the object under `point` (returns false if nothing was hit).
    func beginDrag(at point: CGPoint) -> Bool {
        guard let view = arView, let id = objectID(at: point), let obj = document.objects.first(where: { $0.id == id }),
              let ray = view.ray(through: point) else { return false }
        let normal = simdNormalize(target - cameraPosition)
        let planePoint = obj.position
        guard let hit = Self.intersect(origin: ray.origin, direction: ray.direction, planePoint: planePoint, normal: normal) else { return false }
        checkpoint()
        dragState = (id, planePoint, normal, obj.position - hit)
        select(id: id)
        return true
    }

    func drag(to point: CGPoint) {
        guard let state = dragState, let view = arView, let ray = view.ray(through: point),
              let hit = Self.intersect(origin: ray.origin, direction: ray.direction, planePoint: state.planePoint, normal: state.normal) else { return }
        document.update(state.id) { obj in
            var p = hit + state.offset
            if obj.shape != "group" { p.y = max(p.y, obj.size.y * obj.scale.y / 2 - 0.001) } else { p.y = max(p.y, 0) }
            obj.position = p
        }
        if let e = entities[state.id], let obj = document.objects.first(where: { $0.id == state.id }) { apply(obj, to: e) }
    }

    func endDrag() {
        guard dragState != nil else { return }
        dragState = nil
        scheduleSave()
    }

    var isDragging: Bool { dragState != nil }

    static func intersect(origin: SIMD3<Float>, direction: SIMD3<Float>, planePoint: SIMD3<Float>, normal: SIMD3<Float>) -> SIMD3<Float>? {
        let denom = simdDot(direction, normal)
        guard abs(denom) > 1e-5 else { return nil }
        let t = simdDot(planePoint - origin, normal) / denom
        guard t > 0 else { return nil }
        return origin + direction * t
    }

    /// Scroll-wheel / pinch zoom on the object under the pointer (or the selection).
    func scaleObject(id: String?, by factor: Float) {
        guard let id = id ?? document.selectedID else { return }
        document.update(id) { obj in
            obj.scale = simd_clamp(obj.scale * factor, SIMD3(repeating: 0.05), SIMD3(repeating: 12))
        }
        if let e = entities[id], let obj = document.objects.first(where: { $0.id == id }) { apply(obj, to: e) }
        scheduleSave()
    }

    func rotateObject(id: String, byDegrees degrees: Float) {
        document.update(id) { $0.rotation.y += degrees }
        if let e = entities[id], let obj = document.objects.first(where: { $0.id == id }) { apply(obj, to: e) }
        scheduleSave()
    }

    /// Two-hand gesture: scale/rotate relative to the start of the gesture.
    func beginTwoHandGesture() {
        guard let id = hoveredID ?? document.selectedID, let obj = document.objects.first(where: { $0.id == id }) else { return }
        checkpoint()
        gestureScaleStart = (id, obj.scale, obj.rotation)
    }

    func twoHandGesture(scaleRatio: Float?, rotationRadians: Float?) {
        guard let start = gestureScaleStart else { return }
        document.update(start.id) { obj in
            if let r = scaleRatio { obj.scale = simd_clamp(start.scale * r, SIMD3(repeating: 0.05), SIMD3(repeating: 12)) }
            if let a = rotationRadians { obj.rotation.y = start.rotation.y - a * 180 / Float.pi }
        }
        if let e = entities[start.id], let obj = document.objects.first(where: { $0.id == start.id }) { apply(obj, to: e) }
    }

    func endTwoHandGesture() {
        gestureScaleStart = nil
        scheduleSave()
    }

    // MARK: Persistence

    private var projectURL: URL { JarvisPaths.projects.appendingPathComponent("current.json") }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            self?.save()
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(document) else { return }
        try? data.write(to: projectURL, options: .atomic)
    }

    func load() {
        guard let data = try? Data(contentsOf: projectURL), let doc = try? JSONDecoder().decode(SceneDocument.self, from: data) else { return }
        document = doc
    }

    var documentJSON: String {
        (try? String(data: JSONEncoder().encode(document), encoding: .utf8)) ?? "{}"
    }

    func restore(json: String) {
        guard let data = json.data(using: .utf8), let doc = try? JSONDecoder().decode(SceneDocument.self, from: data) else { return }
        document = doc
        rebuildAll()
    }

    // MARK: Export & snapshot

    /// Export the scene as OBJ (always) and USDZ (when ModelIO supports it). Returns the written files.
    func export(baseName: String = "jarvis-model") -> [URL] {
        var meshes: [(String, MeshData, (SIMD3<Float>) -> SIMD3<Float>)] = []
        for obj in document.objects {
            let objQ = Self.quaternion(obj.rotation)
            let objTransform: (SIMD3<Float>) -> SIMD3<Float> = { p in objQ.act(p * obj.scale) + obj.position }
            if let parts = obj.parts, !parts.isEmpty {
                for part in parts {
                    let pq = Self.quaternion(part.rotation)
                    let data = MeshGenerator.mesh(for: part.shape, size: part.size, param: part.param ?? 0, segments: 32)
                    meshes.append(("\(obj.name)_\(part.shape)", data, { p in objTransform(pq.act(p * part.scale) + part.position) }))
                }
            } else if obj.shape != "text" {
                meshes.append((obj.name, MeshGenerator.mesh(for: obj.shape, size: obj.size, param: obj.param ?? 0, segments: 32), objTransform))
            }
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let objURL = JarvisPaths.exports.appendingPathComponent("\(baseName)-\(stamp).obj")
        var written: [URL] = []
        do {
            try MeshGenerator.obj(meshes.map { (name: $0.0, mesh: $0.1, transform: $0.2) }).write(to: objURL, atomically: true, encoding: .utf8)
            written.append(objURL)
        } catch {
            Log.space.error("OBJ export failed: \(error.localizedDescription)")
            return []
        }
        let asset = MDLAsset(url: objURL)
        for ext in ["usdz", "usdc"] where MDLAsset.canExportFileExtension(ext) {
            let url = JarvisPaths.exports.appendingPathComponent("\(baseName)-\(stamp).\(ext)")
            do {
                try asset.export(to: url)
                written.append(url)
                break
            } catch {
                Log.space.error("\(ext) export failed: \(error.localizedDescription)")
            }
        }
        let jsonURL = JarvisPaths.exports.appendingPathComponent("\(baseName)-\(stamp).jarvis.json")
        if let data = try? JSONEncoder().encode(document), (try? data.write(to: jsonURL)) != nil { written.append(jsonURL) }
        return written
    }

    func snapshot() async -> UIImage? {
        guard let view = arView else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<UIImage?, Never>) in
            view.snapshot(saveToHDR: false) { image in c.resume(returning: image) }
        }
    }
}
