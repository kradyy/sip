import AppKit
import SwiftUI

enum Theme {
    static let aqua = Color(red: 0.36, green: 0.84, blue: 1.0)
    static let cyan = Color(red: 0.20, green: 0.92, blue: 0.86)
    static let deepBlue = Color(red: 0.10, green: 0.38, blue: 0.98)
    static let ink = Color(red: 0.03, green: 0.06, blue: 0.15)
    static let navy = Color(red: 0.05, green: 0.15, blue: 0.33)
    static let flame = Color(red: 1.0, green: 0.56, blue: 0.25)
    static let ice = Color(red: 0.62, green: 0.86, blue: 1.0)
    static let gold = Color(red: 1.0, green: 0.82, blue: 0.36)
    static let violet = Color(red: 0.66, green: 0.55, blue: 1.0)

    static let water = LinearGradient(colors: [aqua, deepBlue], startPoint: .top, endPoint: .bottom)
    static let xp = LinearGradient(colors: [violet, aqua], startPoint: .leading, endPoint: .trailing)
    static let goldGradient = LinearGradient(
        colors: [Color(red: 1, green: 0.9, blue: 0.55), Color(red: 1, green: 0.62, blue: 0.2)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let backdrop = LinearGradient(colors: [navy, ink], startPoint: .top, endPoint: .bottom)
}

// MARK: Water

/// One sine layer of water. Only `level` animates; `phase` is driven by a TimelineView.
nonisolated struct Wave: Shape {
    var level: Double
    var phase: Double
    var amplitude: Double
    var frequency: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let baseY = rect.maxY - rect.height * level
        let amp = amplitude * min(1, level * 8)   // a near-empty glass shouldn't slosh
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        var x = 0.0
        while x <= rect.width + 2 {
            let y = baseY + sin(x / rect.width * .pi * 2 * frequency + phase) * amp
            p.addLine(to: CGPoint(x: rect.minX + x, y: y))
            x += 2
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct WaterView: View {
    var level: Double
    var amplitude = 6.0
    var speed = 1.0
    /// Wave cycles across the width; wide screens want more.
    var waves = 1.0
    @Environment(\.liveAnimations) private var live

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !live)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate * speed
            ZStack {
                Wave(level: level, phase: t * 1.5, amplitude: amplitude, frequency: 1.1 * waves)
                    .fill(Theme.cyan.opacity(0.35))
                Wave(level: level, phase: -t * 2.0 + 1.3, amplitude: amplitude * 0.8, frequency: 1.6 * waves)
                    .fill(Theme.water.opacity(0.65))
                Wave(level: level, phase: t * 2.4 + 2.6, amplitude: amplitude * 0.55, frequency: 0.8 * waves)
                    .fill(Theme.water)
            }
            .drawingGroup()   // one GPU layer per frame instead of three CoreAnimation shapes
        }
        .animation(.spring(duration: 1.2, bounce: 0.25), value: level)
    }
}

/// The round "glass" that fills up through the day.
struct Bottle: View {
    var fraction: Double
    /// Measuring marks, one per sip of the bottle plan (0 = none).
    var steps = 0

    var body: some View {
        GeometryReader { g in
            let d = min(g.size.width, g.size.height)
            ZStack {
                // Static glow behind the glass: a shadow on the animated water would re-blur every frame.
                Circle()
                    .fill(Theme.aqua.opacity(fraction >= 1 ? 0.45 : 0.18))
                    .blur(radius: d * 0.1)
                Circle().fill(RadialGradient(
                    colors: [.white.opacity(0.10), .white.opacity(0.02)],
                    center: .topLeading, startRadius: 0, endRadius: d))
                WaterView(level: min(1, max(0.03, fraction)), amplitude: d * 0.03)
                    .clipShape(Circle())
                Circle().strokeBorder(LinearGradient(
                    colors: [.white.opacity(0.5), .white.opacity(0.05), Theme.aqua.opacity(0.5)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                if steps > 1 {
                    Canvas { gc, size in
                        let r = size.width / 2
                        for i in 1..<steps {
                            let y = size.height * (1 - Double(i) / Double(steps))
                            let edge = r + (r * r - (y - r) * (y - r)).squareRoot()
                            var p = Path()
                            p.move(to: CGPoint(x: edge - 16, y: y))
                            p.addLine(to: CGPoint(x: edge - 5, y: y))
                            gc.stroke(p, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        }
                    }
                }
            }
            .frame(width: d, height: d)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: Celebration

/// A one-shot burst of droplets. Give it a new `.id` to replay.
struct Burst: View {
    var power = 1.0
    @State private var start = Date()
    @State private var particles = (0..<70).map { _ in Particle() }

    struct Particle {
        let angle = Double.random(in: -.pi * 0.95 ... -.pi * 0.05)
        let speed = Double.random(in: 240...600)
        let size = Double.random(in: 5...11)
        let spin = Double.random(in: -6...6)
        let color = [Theme.aqua, Theme.cyan, .white, Theme.gold, Theme.violet].randomElement()!
        let round = Bool.random()
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            Canvas { gc, size in
                guard t < 2.2 else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.42)
                for p in particles {
                    var g = gc
                    g.opacity = max(0, 1 - t / 2.2)
                    g.translateBy(
                        x: origin.x + cos(p.angle) * p.speed * power * t,
                        y: origin.y + sin(p.angle) * p.speed * power * t + 520 * power * t * t)
                    g.rotate(by: .radians(p.spin * t))
                    let r = CGRect(x: -p.size / 2, y: -p.size * 0.7, width: p.size, height: p.size * 1.4)
                    g.fill(p.round ? Path(ellipseIn: r) : Path(roundedRect: r, cornerRadius: 2), with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Icon that pops in with a bounce when it appears.
struct PopIcon: View {
    let symbol: String
    var size = 56.0
    var style: AnyShapeStyle = AnyShapeStyle(Theme.water)
    @State private var trigger = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(style)
            .symbolEffect(.bounce, value: trigger)
            .onAppear { trigger.toggle() }
    }
}

// MARK: Building blocks

extension EnvironmentValues {
    /// False while the view is hidden or idle, so continuous animations stop burning CPU.
    @Entry var liveAnimations = true
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .fullScreenUI

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// The big "I drank it" button. Drawn by hand so it looks the same in key and non-key windows.
struct PrimaryStyle: ButtonStyle {
    var height = 52.0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Capsule().fill(LinearGradient(colors: [Theme.aqua, Theme.deepBlue], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
            .shadow(color: Theme.aqua.opacity(configuration.isPressed ? 0.2 : 0.45), radius: 14, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct ChipStyle: ButtonStyle {
    var on = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(
                    on ? AnyShapeStyle(Theme.water)
                       : AnyShapeStyle(.white.opacity(configuration.isPressed ? 0.16 : 0.08))))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.1)))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

extension View {
    /// Fades the bottom edge of a scroll view so it reads as "there's more below".
    func scrollFade() -> some View {
        scrollIndicators(.automatic).mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 24)
            }
        }
    }

    func card(padding: Double = 12) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.07)))
    }
}

// MARK: Menu bar icon

/// A drop that fills as the day's goal fills. Rendered once per 5% step and cached.
enum DropIcon {
    private static var cache: [Int: NSImage] = [:]

    static func image(fraction: Double) -> NSImage {
        let step = Int((min(max(fraction, 0), 1) * 20).rounded())
        if let hit = cache[step] { return hit }
        let renderer = ImageRenderer(content: Glyph(fill: Double(step) / 20))
        renderer.scale = 2
        let img = renderer.nsImage ?? NSImage()
        img.size = NSSize(width: 14, height: 18)
        img.isTemplate = true
        cache[step] = img
        return img
    }

    private struct Glyph: View {
        var fill: Double

        var body: some View {
            ZStack {
                Image(systemName: "drop").font(.system(size: 14, weight: .semibold))
                Image(systemName: "drop.fill").font(.system(size: 14, weight: .semibold))
                    .mask(alignment: .bottom) {
                        GeometryReader { g in
                            Rectangle()
                                .frame(height: g.size.height * fill)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
            }
            .foregroundStyle(.black)
            .frame(width: 14, height: 18)
        }
    }
}

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let f = min(1, model.stats.todayFraction)
        HStack(spacing: 3) {
            Image(nsImage: DropIcon.image(fraction: f))
            Text("\(Int((f * 100).rounded()))%").monospacedDigit()
        }
    }
}
