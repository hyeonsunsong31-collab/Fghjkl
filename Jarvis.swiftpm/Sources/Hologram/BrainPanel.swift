import SwiftUI

/// Holographic view of the 206-billion-neuron synaptic-perceptron brain:
/// a rotating 3D point cloud (cortex shell, subcortical core with the
/// thalamus, folded cerebellum) with live activity, neuromodulators and the
/// output-control score.
struct BrainPanel: View {
    @Environment(JarvisController.self) private var jarvis
    @State private var points: [BrainPoint] = []
    @State private var census: [BrainSystem: UInt64] = [:]
    @State private var synapses: UInt64 = 0
    @State private var drag: CGSize = .zero
    @State private var baseRotation: Double = 0

    struct BrainPoint {
        var position: SIMD3<Float>
        var system: BrainSystem
        var id: NeuronID
    }

    private var ko: Bool { jarvis.currentLanguage == .korean }

    var body: some View {
        PanelContainer(title: ko ? "신경 코어 · 시냅스 퍼셉트론 3D 뇌" : "Neural core · synaptic-perceptron 3D brain",
                       icon: "brain.head.profile", close: { jarvis.showPanel(nil) }) {
            HStack(alignment: .top, spacing: 14) {
                cloud
                    .frame(minWidth: 260, minHeight: 260)
                    .gesture(DragGesture().onChanged { drag = $0.translation }.onEnded { v in
                        baseRotation += Double(v.translation.width) * 0.01
                        drag = .zero
                    })
                stats.frame(width: 250)
            }
        }
        .onAppear(perform: prepare)
    }

    private var cloud: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let active = Set(jarvis.latticeSample)
            Canvas { ctx, size in
                let yaw = Float(baseRotation + Double(drag.width) * 0.01 + t * 0.15)
                let pitch = Float(-0.25 + Double(drag.height) * 0.005)
                let scale = Float(min(size.width, size.height)) * 0.36
                let cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch)
                for p in points {
                    var v = p.position
                    v = SIMD3(v.x * cy + v.z * sy, v.y, -v.x * sy + v.z * cy)
                    v = SIMD3(v.x, v.y * cp - v.z * sp, v.y * sp + v.z * cp)
                    let depth = 1 / (2.6 - v.z)
                    let x = CGFloat(v.x * scale * depth * 2.2) + size.width / 2
                    let y = CGFloat(-v.y * scale * depth * 2.2) + size.height / 2
                    let isActive = active.contains(p.id)
                    let r: CGFloat = isActive ? 3.2 : CGFloat(1.1 + depth)
                    let color = Self.color(p.system).opacity(isActive ? 1 : Double(0.25 + depth * 0.5))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)), with: .color(color))
                }
                // Live spikes from the lattice simulator, projected near their region.
                for (i, id) in jarvis.latticeSample.prefix(160).enumerated() {
                    let region = Lattice3D.region(of: id)
                    let base = Self.anatomical(Lattice3D.coordinate(id), region: region)
                    var v = base
                    v = SIMD3(v.x * cy + v.z * sy, v.y, -v.x * sy + v.z * cy)
                    v = SIMD3(v.x, v.y * cp - v.z * sp, v.y * sp + v.z * cp)
                    let depth = 1 / (2.6 - v.z)
                    let x = CGFloat(v.x * scale * depth * 2.2) + size.width / 2
                    let y = CGFloat(-v.y * scale * depth * 2.2) + size.height / 2
                    let flicker = 0.5 + 0.5 * sin(t * 12 + Double(i))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)), with: .color(Color.white.opacity(flicker)))
                }
            }
            .holoGlow(Holo.cyan, radius: 6)
        }
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 8) {
            statRow(ko ? "총 퍼셉트론" : "Total perceptrons", Lattice3D.totalNeurons.formatted())
            statRow(ko ? "논리 시냅스" : "Logical synapses", String(format: "%.2e", Double(synapses)))
            statRow(ko ? "상시 계산 코어" : "Dense core", "\(jarvis.brain.coreNeuronCount.formatted()) · \(jarvis.brain.coreSynapseCount.formatted()) syn")
            statRow(ko ? "학습된 Δw" : "Learned Δw", jarvis.brain.connectome.plasticity.count.formatted())
            statRow(ko ? "출력 제어 점수" : "Output control", "\(Int(jarvis.brain.controlScore * 100))%")
            statRow(ko ? "결정 수" : "Decisions", jarvis.brain.decisionsMade.formatted())
            Divider().overlay(Holo.cyan.opacity(0.3))
            ForEach(BrainSystem.allCases, id: \.self) { s in
                HStack {
                    Circle().fill(Self.color(s)).frame(width: 7, height: 7)
                    Text(ko ? s.koreanName : s.rawValue).font(Holo.mono(10)).foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text(Self.short(census[s] ?? 0)).font(Holo.mono(10)).foregroundStyle(Holo.ice.opacity(0.7))
                    if let a = jarvis.latticeStats?.activity[s] { Text("⚡︎\(a)").font(Holo.mono(9)).foregroundStyle(Holo.amber) }
                }
            }
            Divider().overlay(Holo.cyan.opacity(0.3))
            let m = jarvis.brain.modulators
            modulator("DA", (m.dopamine + 1) / 2, Holo.green)
            modulator("ACh", m.acetylcholine, Holo.cyan)
            modulator("NE", m.noradrenaline, Holo.amber)
            modulator("5-HT", m.serotonin, Color.purple)
            if let s = jarvis.latticeStats {
                Text(ko ? "격자 틱: 스파이크 \(s.spikes) · 시냅스 이벤트 \(s.synapticEvents)" : "Lattice tick: \(s.spikes) spikes · \(s.synapticEvents) events")
                    .font(Holo.mono(9)).foregroundStyle(Holo.ice.opacity(0.7))
            }
        }
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(Holo.mono(10)).foregroundStyle(Holo.ice.opacity(0.7))
            Spacer()
            Text(value).font(Holo.mono(11, .bold)).foregroundStyle(Holo.cyan)
        }
    }

    private func modulator(_ name: String, _ value: Float, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(name).font(Holo.mono(9, .bold)).foregroundStyle(color).frame(width: 34, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule().fill(color.opacity(0.8)).frame(width: g.size.width * CGFloat(max(0, min(1, value))))
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: Geometry

    private func prepare() {
        guard points.isEmpty else { return }
        census = Lattice3D.systemCensus()
        synapses = ProceduralConnectome.logicalSynapseCount()
        var rng = SplitMix64(seed: 2026)
        var out: [BrainPoint] = []
        let perRegion: [BrainRegion: Int] = Dictionary(uniqueKeysWithValues: BrainRegion.allCases.map { r in
            switch r.system {
            case .cortex: return (r, 380)
            case .cerebellum: return (r, r == .cerebellumGranule ? 900 : 120)
            default: return (r, 70)
            }
        })
        for (region, n) in perRegion {
            for _ in 0..<n {
                let c = Lattice3D.sample(in: region, u: rng.nextUnit(), v: rng.nextUnit(), w: rng.nextUnit(), hash: rng.next())
                out.append(BrainPoint(position: Self.anatomical(c, region: region), system: region.system, id: Lattice3D.id(c)))
            }
        }
        // Include the core neurons of the dense circuits so decisions light them up.
        points = out
    }

    /// Map lattice (index-space) coordinates onto a stylised anatomical shape.
    static func anatomical(_ c: LatticeCoordinate, region: BrainRegion) -> SIMD3<Float> {
        let (u, v, w) = Lattice3D.normalisedPosition(c, in: region)
        let fu = Float(u), fv = Float(v), fw = Float(w)
        switch region.system {
        case .cortex:
            // Shell of an ellipsoid; layer depth shrinks the radius slightly.
            let theta = fw * .pi              // left ↔ right
            let phi = fv * .pi * 0.95 + 0.1     // bottom ↔ top
            let depth: Float = {
                switch region {
                case .cortexL1: return 1.0
                case .cortexL23: return 0.97
                case .cortexL4: return 0.94
                case .cortexL5: return 0.91
                default: return 0.88
                }
            }()
            let ap = (fu - 0.5) * 0.25
            return SIMD3(cos(theta) * sin(phi) * 0.82 * depth, cos(phi) * 0.62 * depth + 0.15, sin(theta) * sin(phi) * 1.0 * depth + ap) * SIMD3(1, 1, 1)
        case .cerebellum:
            let fold = sin(fv * 16 * .pi) * 0.04
            return SIMD3((fw - 0.5) * 0.9, -0.48 + (fv - 0.5) * 0.25 + fold, -0.55 - (fu - 0.5) * 0.35)
        default:
            return SIMD3((fw - 0.5) * 0.42, -0.1 + (fv - 0.5) * 0.5, (fu - 0.5) * 0.4)
        }
    }

    static func color(_ s: BrainSystem) -> Color {
        switch s {
        case .cortex: return Holo.cyan
        case .cerebellum: return Color(red: 0.62, green: 0.45, blue: 1)
        case .thalamus: return Holo.amber
        case .basalGanglia: return Holo.green
        case .hippocampus: return Color(red: 1, green: 0.45, blue: 0.75)
        case .amygdala: return Holo.red
        case .hypothalamus: return Color(red: 1, green: 0.9, blue: 0.4)
        case .brainstem: return Holo.ice
        }
    }

    static func short(_ n: UInt64) -> String {
        let d = Double(n)
        if d >= 1e9 { return String(format: "%.1fB", d / 1e9) }
        if d >= 1e6 { return String(format: "%.1fM", d / 1e6) }
        return n.formatted()
    }
}
