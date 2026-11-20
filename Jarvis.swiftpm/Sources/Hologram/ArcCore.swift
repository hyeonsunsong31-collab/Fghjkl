import SwiftUI

/// The animated holographic core — Jarvis' "face". Concentric segmented rings
/// rotate at different speeds; colour follows the assistant phase and the
/// inner disc breathes with the microphone level or the voice.
struct ArcCore: View {
    var phase: AssistantPhase
    var level: Float
    var size: CGFloat = 220

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, canvasSize in
                let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let base = min(canvasSize.width, canvasSize.height) / 2
                let color = Holo.phaseColor(phase)
                let activity = phase == .asleep ? 0.15 : (phase == .thinking ? 1.0 : 0.6)
                let breath = 0.5 + 0.5 * sin(t * (phase == .thinking ? 4 : 1.6))
                let voice = Double(level)

                // Outer tick ring.
                for k in 0..<120 {
                    let a = Double(k) / 120 * 2 * .pi + t * 0.05
                    let long = k % 10 == 0
                    let r1 = base * 0.98, r2 = base * (long ? 0.88 : 0.93)
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + r1 * cos(a), y: c.y + r1 * sin(a)))
                    p.addLine(to: CGPoint(x: c.x + r2 * cos(a), y: c.y + r2 * sin(a)))
                    ctx.stroke(p, with: .color(color.opacity(long ? 0.7 : 0.3)), lineWidth: long ? 1.6 : 0.8)
                }

                // Segmented rings (radius, segments, gap, speed, width, opacity).
                let rings: [(Double, Int, Double, Double, Double, Double)] = [
                    (0.82, 6, 0.18, 0.35, 3.0, 0.85),
                    (0.72, 24, 0.35, -0.6, 2.0, 0.55),
                    (0.62, 3, 0.45, 1.1, 5.0, 0.9),
                    (0.52, 48, 0.5, -0.25, 1.2, 0.5),
                ]
                for (radius, segments, gap, speed, width, opacity) in rings {
                    let r = base * radius
                    let seg = 2 * .pi / Double(segments)
                    for s in 0..<segments {
                        let start = Double(s) * seg + t * speed * activity
                        var arc = Path()
                        arc.addArc(center: c, radius: r, startAngle: .radians(start), endAngle: .radians(start + seg * (1 - gap)), clockwise: false)
                        ctx.stroke(arc, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineCap: .round))
                    }
                }

                // Inner glow disc.
                let inner = base * (0.30 + 0.05 * breath + 0.12 * voice)
                let gradient = Gradient(colors: [Color.white.opacity(0.95), color.opacity(0.85), color.opacity(0.0)])
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - inner * 1.6, y: c.y - inner * 1.6, width: inner * 3.2, height: inner * 3.2)),
                         with: .radialGradient(gradient, center: c, startRadius: 0, endRadius: inner * 1.6))
                // Triangular frame (an original motif).
                var tri = Path()
                for k in 0..<3 {
                    let a = Double(k) * 2 * .pi / 3 - .pi / 2 + t * 0.2 * activity
                    let pt = CGPoint(x: c.x + inner * 1.05 * cos(a), y: c.y + inner * 1.05 * sin(a))
                    if k == 0 { tri.move(to: pt) } else { tri.addLine(to: pt) }
                }
                tri.closeSubpath()
                ctx.stroke(tri, with: .color(Color.white.opacity(0.75)), lineWidth: 1.5)
            }
            .holoGlow(Holo.phaseColor(phase), radius: 14)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Jarvis core, \(phase.rawValue)")
    }
}

/// Live audio-level waveform bar.
struct HoloWaveform: View {
    var level: Float
    var color: Color = Holo.cyan
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let bars = 32
                let w = size.width / CGFloat(bars)
                for i in 0..<bars {
                    let phase = Double(i) / Double(bars) * 2 * .pi
                    let h = max(2, CGFloat(Double(level) * (0.5 + 0.5 * sin(phase * 3 + t * 9))) * size.height)
                    let rect = CGRect(x: CGFloat(i) * w + w * 0.2, y: (size.height - h) / 2, width: w * 0.6, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: w * 0.3), with: .color(color.opacity(0.85)))
                }
            }
        }
        .holoGlow(color, radius: 5)
    }
}
