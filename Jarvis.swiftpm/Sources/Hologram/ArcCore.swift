import SwiftUI

// Drawing code here is written as small, explicitly typed statements (CGFloat
// throughout, no tuples or mixed Double/CGFloat maths): the Swift compiler bundled
// with Swift Playground gives up type-checking large drawing closures.

/// The animated holographic core: Jarvis' "face". Concentric segmented rings
/// rotate at different speeds; colour follows the assistant phase and the
/// inner disc breathes with the microphone level or the voice.
struct ArcCore: View {
    var phase: AssistantPhase
    var level: Float
    var size: CGFloat = 220
    var paused = false

    var body: some View {
        // 30 fps is smooth for slow rings; uncapped, a 120 Hz iPad redrew this 120 times a second.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { (context: TimelineViewDefaultContext) in
            ArcCoreCanvas(phase: phase, level: level, time: context.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Jarvis core, \(phase.rawValue)")
    }
}

private struct ArcCoreCanvas: View {
    let phase: AssistantPhase
    let level: Float
    let time: TimeInterval

    var body: some View {
        let state = ArcCoreDrawing.State(phase: phase, level: CGFloat(level), time: CGFloat(time))
        return Canvas { (ctx: inout GraphicsContext, canvasSize: CGSize) in
            ArcCoreDrawing.draw(in: &ctx, size: canvasSize, state: state)
        }
        .holoGlow(Holo.phaseColor(phase), radius: 14)
    }
}

enum ArcCoreDrawing {
    struct State {
        let phase: AssistantPhase
        let level: CGFloat
        let time: CGFloat
    }

    struct Ring {
        let radius: CGFloat
        let segments: Int
        let gap: CGFloat
        let speed: CGFloat
        let width: CGFloat
        let opacity: Double
    }

    static let rings: [Ring] = [
        Ring(radius: 0.82, segments: 6, gap: 0.18, speed: 0.35, width: 3.0, opacity: 0.85),
        Ring(radius: 0.72, segments: 24, gap: 0.35, speed: -0.6, width: 2.0, opacity: 0.55),
        Ring(radius: 0.62, segments: 3, gap: 0.45, speed: 1.1, width: 5.0, opacity: 0.9),
        Ring(radius: 0.52, segments: 48, gap: 0.5, speed: -0.25, width: 1.2, opacity: 0.5),
    ]

    static func activity(_ phase: AssistantPhase) -> CGFloat {
        switch phase {
        case .asleep: return 0.15
        case .thinking: return 1.0
        case .listening, .speaking: return 0.6
        }
    }

    static func draw(in ctx: inout GraphicsContext, size: CGSize, state: State) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let base: CGFloat = min(size.width, size.height) / 2
        let color: Color = Holo.phaseColor(state.phase)
        let activityLevel: CGFloat = Self.activity(state.phase)
        let breathRate: CGFloat = state.phase == .thinking ? 4 : 1.6
        let breath: CGFloat = 0.5 + 0.5 * sin(state.time * breathRate)
        drawTicks(in: &ctx, center: center, base: base, color: color, time: state.time)
        drawRings(in: &ctx, center: center, base: base, color: color, time: state.time, activity: activityLevel)
        let scale: CGFloat = 0.30 + 0.05 * breath + 0.12 * state.level
        let inner: CGFloat = base * scale
        drawCore(in: &ctx, center: center, inner: inner, color: color, time: state.time, activity: activityLevel)
    }

    static func point(_ center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
        let x: CGFloat = center.x + radius * cos(angle)
        let y: CGFloat = center.y + radius * sin(angle)
        return CGPoint(x: x, y: y)
    }

    static func drawTicks(in ctx: inout GraphicsContext, center: CGPoint, base: CGFloat, color: Color, time: CGFloat) {
        let outer: CGFloat = base * 0.98
        let longInner: CGFloat = base * 0.88
        let shortInner: CGFloat = base * 0.93
        let longShading = GraphicsContext.Shading.color(color.opacity(0.7))
        let shortShading = GraphicsContext.Shading.color(color.opacity(0.3))
        for k in 0..<120 {
            let fraction: CGFloat = CGFloat(k) / 120
            let angle: CGFloat = fraction * 2 * CGFloat.pi + time * 0.05
            let isLong: Bool = k % 10 == 0
            var path = Path()
            path.move(to: point(center, radius: outer, angle: angle))
            path.addLine(to: point(center, radius: isLong ? longInner : shortInner, angle: angle))
            ctx.stroke(path, with: isLong ? longShading : shortShading, lineWidth: isLong ? 1.6 : 0.8)
        }
    }

    static func drawRings(in ctx: inout GraphicsContext, center: CGPoint, base: CGFloat, color: Color,
                          time: CGFloat, activity: CGFloat) {
        for ring in rings {
            let radius: CGFloat = base * ring.radius
            let segment: CGFloat = 2 * CGFloat.pi / CGFloat(ring.segments)
            let sweep: CGFloat = segment * (1 - ring.gap)
            let rotation: CGFloat = time * ring.speed * activity
            let shading = GraphicsContext.Shading.color(color.opacity(ring.opacity))
            let style = StrokeStyle(lineWidth: ring.width, lineCap: .round)
            for s in 0..<ring.segments {
                let start: CGFloat = CGFloat(s) * segment + rotation
                var arc = Path()
                arc.addArc(center: center, radius: radius, startAngle: Angle(radians: Double(start)),
                           endAngle: Angle(radians: Double(start + sweep)), clockwise: false)
                ctx.stroke(arc, with: shading, style: style)
            }
        }
    }

    static func drawCore(in ctx: inout GraphicsContext, center: CGPoint, inner: CGFloat, color: Color,
                         time: CGFloat, activity: CGFloat) {
        let glowRadius: CGFloat = inner * 1.6
        let colors: [Color] = [Color.white.opacity(0.95), color.opacity(0.85), color.opacity(0.0)]
        let disc = CGRect(x: center.x - glowRadius, y: center.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)
        let shading = GraphicsContext.Shading.radialGradient(Gradient(colors: colors), center: center,
                                                             startRadius: 0, endRadius: glowRadius)
        ctx.fill(Path(ellipseIn: disc), with: shading)
        // Triangular frame (an original motif).
        var triangle = Path()
        let spin: CGFloat = time * 0.2 * activity
        for k in 0..<3 {
            let angle: CGFloat = CGFloat(k) * 2 * CGFloat.pi / 3 - CGFloat.pi / 2 + spin
            let corner: CGPoint = point(center, radius: inner * 1.05, angle: angle)
            if k == 0 { triangle.move(to: corner) } else { triangle.addLine(to: corner) }
        }
        triangle.closeSubpath()
        ctx.stroke(triangle, with: GraphicsContext.Shading.color(Color.white.opacity(0.75)), lineWidth: 1.5)
    }
}

/// The core, reading the live phase and microphone level itself (so only it redraws when they change).
struct LiveArcCore: View {
    @Environment(JarvisController.self) private var jarvis
    var size: CGFloat

    var body: some View {
        let speaking: Bool = jarvis.phase == .speaking
        ArcCore(phase: jarvis.phase, level: speaking ? 0.6 : jarvis.inputLevel, size: size, paused: jarvis.typing)
    }
}

/// The waveform, reading the live level itself.
struct LiveWaveform: View {
    @Environment(JarvisController.self) private var jarvis

    var body: some View {
        HoloWaveform(level: jarvis.inputLevel, color: Holo.phaseColor(jarvis.phase), paused: jarvis.typing)
    }
}

/// Live audio-level waveform bar.
struct HoloWaveform: View {
    var level: Float
    var color: Color = Holo.cyan
    var paused = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: paused)) { (context: TimelineViewDefaultContext) in
            WaveformCanvas(level: CGFloat(level), color: color, time: CGFloat(context.date.timeIntervalSinceReferenceDate))
        }
        .holoGlow(color, radius: 5)
    }
}

private struct WaveformCanvas: View {
    let level: CGFloat
    let color: Color
    let time: CGFloat

    var body: some View {
        Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            WaveformCanvas.draw(in: &ctx, size: size, level: level, color: color, time: time)
        }
    }

    static func draw(in ctx: inout GraphicsContext, size: CGSize, level: CGFloat, color: Color, time: CGFloat) {
        let bars = 32
        let width: CGFloat = size.width / CGFloat(bars)
        let shading = GraphicsContext.Shading.color(color.opacity(0.85))
        for i in 0..<bars {
            let phase: CGFloat = CGFloat(i) / CGFloat(bars) * 2 * CGFloat.pi
            let wave: CGFloat = 0.5 + 0.5 * sin(phase * 3 + time * 9)
            let height: CGFloat = max(2, level * wave * size.height)
            let x: CGFloat = CGFloat(i) * width + width * 0.2
            let rect = CGRect(x: x, y: (size.height - height) / 2, width: width * 0.6, height: height)
            ctx.fill(Path(roundedRect: rect, cornerRadius: width * 0.3), with: shading)
        }
    }
}
