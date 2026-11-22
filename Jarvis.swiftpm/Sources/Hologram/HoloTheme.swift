import SwiftUI

/// Original holographic design language (deep navy space, cyan light, amber accents).
enum Holo {
    static let cyan = Color(red: 0.0, green: 0.90, blue: 1.0)
    static let ice = Color(red: 0.70, green: 0.95, blue: 1.0)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.25)
    static let red = Color(red: 1.0, green: 0.30, blue: 0.32)
    static let green = Color(red: 0.30, green: 1.0, blue: 0.62)
    static let deep = Color(red: 0.008, green: 0.024, blue: 0.065)
    static let panel = Color(red: 0.02, green: 0.09, blue: 0.16).opacity(0.55)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func phaseColor(_ phase: AssistantPhase) -> Color {
        switch phase {
        case .asleep: return ice.opacity(0.55)
        case .listening: return cyan
        case .thinking: return amber
        case .speaking: return .white
        }
    }
}

/// Glow made of stacked additive shadows.
struct HoloGlow: ViewModifier {
    var color: Color = Holo.cyan
    var radius: CGFloat = 8
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.85), radius: radius * 0.25)
            .shadow(color: color.opacity(0.55), radius: radius * 0.7)
            .shadow(color: color.opacity(0.30), radius: radius * 1.6)
    }
}

extension View {
    func holoGlow(_ color: Color = Holo.cyan, radius: CGFloat = 8) -> some View { modifier(HoloGlow(color: color, radius: radius)) }

    func holoPanel(corner: CGFloat = 14, tint: Color = Holo.cyan) -> some View {
        self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous).fill(.ultraThinMaterial).opacity(0.55)
                    RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Holo.panel)
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.12), .clear, tint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            )
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(tint.opacity(0.45), lineWidth: 1))
            .overlay(CornerBrackets(length: 14).stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round)).padding(-3))
    }
}

/// Four corner brackets — the signature frame of every hologram panel.
struct CornerBrackets: Shape {
    var length: CGFloat = 12
    func path(in r: CGRect) -> Path {
        var p = Path()
        let l = min(length, r.width / 3, r.height / 3)
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

/// Holographic button with icon, label, active state and press feedback.
struct HoloButton: View {
    let icon: String
    let label: String
    var active = false
    var tint: Color = Holo.cyan
    var compact = false
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            VStack(spacing: compact ? 3 : 6) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 16 : 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .holoGlow(active ? tint : tint.opacity(0.5), radius: active ? 10 : 4)
                if !label.isEmpty {
                    Text(label)
                        .font(Holo.mono(compact ? 9 : 10, .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(active ? tint : Holo.ice.opacity(0.9))
            .frame(minWidth: compact ? 52 : 64, minHeight: compact ? 46 : 58)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? tint.opacity(0.18) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(active ? tint.opacity(0.9) : tint.opacity(0.28), lineWidth: active ? 1.4 : 1)
            )
            .scaleEffect(pressed ? 0.94 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false })
        .hoverEffect(.highlight)
        .accessibilityLabel(label.isEmpty ? icon : label)
    }
}

/// Animated scanlines + subtle flicker overlay.
struct Scanlines: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let spacing: CGFloat = 3
                var y: CGFloat = CGFloat((t * 12).truncatingRemainder(dividingBy: Double(spacing)))
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Holo.cyan.opacity(0.035)))
                    y += spacing
                }
                // A slow bright sweep.
                let sweep = CGFloat((t * 0.25).truncatingRemainder(dividingBy: 1)) * (size.height + 200) - 100
                let rect = CGRect(x: 0, y: sweep, width: size.width, height: 90)
                ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [.clear, Holo.cyan.opacity(0.05), .clear]),
                                                          startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
            }
        }
        .allowsHitTesting(false)
        .blendMode(.plusLighter)
    }
}

/// Animated hexagonal grid backdrop (used when the 3D space is closed).
struct HexBackdrop: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { (context: TimelineViewDefaultContext) in
            HexBackdropCanvas(time: CGFloat(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000)))
        }
        .ignoresSafeArea()
    }
}

/// Explicitly typed drawing (fast to type-check on Swift Playground's compiler).
private struct HexBackdropCanvas: View {
    let time: CGFloat

    var body: some View {
        Canvas { (ctx: inout GraphicsContext, size: CGSize) in
            HexBackdropCanvas.draw(in: &ctx, size: size, time: time)
        }
    }

    static func draw(in ctx: inout GraphicsContext, size: CGSize, time: CGFloat) {
        let focus = CGPoint(x: size.width / 2, y: size.height * 0.42)
        let background = Gradient(colors: [Color(red: 0.02, green: 0.10, blue: 0.20), Holo.deep])
        let reach: CGFloat = max(size.width, size.height) * 0.75
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: GraphicsContext.Shading.radialGradient(background, center: focus, startRadius: 0, endRadius: reach))
        let r: CGFloat = 26
        let w: CGFloat = r * 1.732
        let falloff: CGFloat = size.width * 0.8
        var row = 0
        var y: CGFloat = 0
        while y < size.height + r {
            var x: CGFloat = row % 2 == 0 ? 0 : w / 2
            while x < size.width + w {
                let d: CGFloat = hypot(x - focus.x, y - focus.y)
                let pulse: CGFloat = 0.5 + 0.5 * sin(d / 60 - time * 1.4)
                let fade: CGFloat = max(0, 1 - d / falloff)
                let alpha: Double = Double(0.025 + 0.06 * pulse * fade)
                ctx.stroke(hexagon(center: CGPoint(x: x, y: y), radius: r * 0.92),
                           with: GraphicsContext.Shading.color(Holo.cyan.opacity(alpha)), lineWidth: 1)
                x += w
            }
            y += r * 1.5
            row += 1
        }
    }

    static func hexagon(center: CGPoint, radius: CGFloat) -> Path {
        var hex = Path()
        for k in 0..<6 {
            let angle: CGFloat = CGFloat(k) * CGFloat.pi / 3 + CGFloat.pi / 6
            let corner = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if k == 0 { hex.move(to: corner) } else { hex.addLine(to: corner) }
        }
        hex.closeSubpath()
        return hex
    }
}

/// Small monospaced label used throughout the HUD.
struct HUDLabel: View {
    let text: String
    var color: Color = Holo.ice
    var size: CGFloat = 10
    var body: some View {
        Text(text.uppercased())
            .font(Holo.mono(size, .semibold))
            .tracking(1.2)
            .foregroundStyle(color.opacity(0.85))
    }
}
