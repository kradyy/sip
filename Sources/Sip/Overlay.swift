import AppKit
import SipCore
import SwiftUI

/// Borderless panels can't take keyboard focus unless told so. Only the full-screen card panel may;
/// banners and secondary screens never steal the keyboard from the app you're typing in.
private final class OverlayPanel: NSPanel {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { allowsKey }
}

/// Non-key panels still need buttons to work on the first click.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Puts the reminder above everything: every screen, every Space, full-screen apps included.
final class OverlayController {
    private var panels: [NSPanel] = []

    /// False when there is no screen to show on.
    func show(style: ReminderStyle, model: AppModel, id: UUID) -> Bool {
        hide(animated: false)
        let mouse = NSEvent.mouseLocation
        guard let focus = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        else { return false }

        var keyPanel: OverlayPanel?
        switch style {
        case .fullscreen:
            for screen in NSScreen.screens {
                let isFocus = screen == focus
                let p = makePanel(frame: screen.frame, level: .screenSaver,
                                  content: OverlayView(model: model, id: id, compact: false, showsCard: isFocus))
                if isFocus {
                    p.allowsKey = true
                    keyPanel = p
                }
                panels.append(p)
            }
        case .banner:
            let size = CGSize(width: 400, height: 380)
            let vf = focus.visibleFrame
            let frame = CGRect(x: vf.maxX - size.width, y: vf.maxY - size.height,
                               width: size.width, height: size.height)
            panels.append(makePanel(frame: frame, level: .statusBar,
                                    content: OverlayView(model: model, id: id, compact: true, showsCard: true)))
        }

        for p in panels {
            p.alphaValue = 0
            p.orderFrontRegardless()
        }
        keyPanel?.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            for p in panels { p.animator().alphaValue = 1 }
        }
        return true
    }

    func hide(animated: Bool = true) {
        let closing = panels
        panels = []
        closing.forEach { $0.ignoresMouseEvents = true }   // no double taps while fading out
        guard animated else {
            closing.forEach(Self.tearDown)
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            for p in closing { p.animator().alphaValue = 0 }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            closing.forEach(Self.tearDown)
        }
    }

    private static func tearDown(_ p: NSPanel) {
        p.orderOut(nil)
        p.contentView = nil   // drop the SwiftUI tree so its animations stop
        p.close()
    }

    private func makePanel(frame: CGRect, level: NSWindow.Level, content: some View) -> OverlayPanel {
        let p = OverlayPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.level = level
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = FirstMouseHostingView(rootView: content)
        host.sizingOptions = []   // the panel decides its size, not SwiftUI
        p.contentView = host
        p.setFrame(frame, display: false)
        return p
    }
}

/// A captcha-style "I'm not a robot" box: click → spinner → check → done.
private struct CaptchaCheck: View {
    let ml: Int
    let action: (Int) -> Void
    @State private var phase = 0   // 0 unchecked, 1 verifying, 2 checked
    @State private var ticked: Int?   // the amount ticked, kept even if a chip is clicked while verifying

    var body: some View {
        Button {
            guard phase == 0 else { return }
            let chosen = ml
            ticked = chosen
            withAnimation(.easeOut(duration: 0.2)) { phase = 1 }
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                withAnimation(.spring(duration: 0.35, bounce: 0.5)) { phase = 2 }
                try? await Task.sleep(for: .milliseconds(350))
                action(chosen)
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white.opacity(0.65), lineWidth: 2)
                        .opacity(phase == 0 ? 1 : 0)
                    if phase == 1 { ProgressView().controlSize(.small) }
                    if phase == 2 {
                        Image(systemName: "checkmark")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(Theme.cyan)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
                .frame(width: 30, height: 30)
                Text("I drank \(ticked ?? ml) ml").font(.system(size: 17, weight: .semibold))
                Spacer()
                VStack(spacing: 2) {
                    Image(systemName: "drop.fill").foregroundStyle(Theme.water)
                    Text("hydration check").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.15)))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

/// Fires only after being held down for `seconds`; the fill shows progress.
private struct HoldButton: View {
    let title: String
    let seconds: Double
    let action: () -> Void
    @State private var holding = false

    var body: some View {
        Text(title)
            .font(.callout.weight(.medium))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(alignment: .leading) {
                GeometryReader { g in
                    Capsule().fill(.white.opacity(0.2)).frame(width: holding ? g.size.width : 0)
                }
            }
            .background(Capsule().fill(.white.opacity(0.06)))
            .clipShape(Capsule())
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: seconds, perform: action) { pressing in
                withAnimation(pressing ? .linear(duration: seconds) : .easeOut(duration: 0.25)) { holding = pressing }
            }
    }
}

private enum Lines {
    static let all: [(String, String)] = [
        ("Time for a sip", "Your brain runs on water. Top it up."),
        ("Hydration check", "Future you says thanks."),
        ("Water you waiting for?", "One glass. Ten seconds."),
        ("Sip happens", "Make it happen now."),
        ("Refill o'clock", "Small sips, big wins."),
        ("Drink up, legend", "Every glass is XP."),
        ("Psst… water", "Headaches hate this one trick."),
    ]
}

struct OverlayView: View {
    let model: AppModel
    let id: UUID
    let compact: Bool
    let showsCard: Bool

    @State private var shown = false
    /// Input is ignored for the first second, so a Return or click already on its way
    /// into another app doesn't log a drink by accident.
    @State private var armed = false
    /// After a minute unanswered (you're probably away) the water stops moving to save power.
    @State private var calm = false
    @State private var result: Celebration?
    @State private var line = Lines.all.randomElement()!

    /// Captcha mode: a full-screen reminder can't be dismissed for `lockSeconds`, giving you time to
    /// actually go drink. Then it unlocks into an "I drank it" checkbox.
    private let lockSeconds: Int
    private let unlockAt: Date
    @State private var unlocked: Bool
    @State private var pickedML: Int
    private var captcha: Bool { lockSeconds > 0 }

    init(model: AppModel, id: UUID, compact: Bool, showsCard: Bool) {
        self.model = model
        self.id = id
        self.compact = compact
        self.showsCard = showsCard
        let lock = compact ? 0 : model.prefs.effectiveLockSeconds
        lockSeconds = lock
        unlockAt = Date().addingTimeInterval(TimeInterval(lock))
        _unlocked = State(initialValue: lock == 0)
        _pickedML = State(initialValue: model.prefs.glassML)
    }

    var body: some View {
        ZStack {
            if !compact {
                VisualEffect().ignoresSafeArea()
                Theme.backdrop.opacity(0.55).ignoresSafeArea()
                RadialGradient(colors: [Theme.aqua.opacity(0.22), .clear], center: .center,
                               startRadius: 0, endRadius: 520)
                    .opacity(showsCard ? 1 : 0)
                WaterView(level: shown ? (result == nil ? 0.16 : 0.3) : 0, amplitude: 26, speed: 0.55, waves: 2.4)
                    .opacity(0.42)
                    .ignoresSafeArea()
            }
            if showsCard {
                card
                    .padding(compact ? 14 : 0)   // room for the shadow inside the banner window
                    .scaleEffect(shown ? 1 : 0.9)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 30)
                    .allowsHitTesting(armed && result == nil)
            }
            if let result, showsCard {
                Burst(power: compact ? 0.6 : 1.4).id(result.id)
            }
        }
        // Fill the panel: without this a banner window shrinks to the card and clips its shadow.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .topTrailing : .center)
        .environment(\.colorScheme, .dark)
        .environment(\.liveAnimations, !calm)
        .fontDesign(.rounded)
        .onAppear { withAnimation(.spring(duration: 0.7, bounce: 0.3)) { shown = true } }
        .task {
            try? await Task.sleep(for: .seconds(1))
            armed = true
        }
        .task {
            if !unlocked {
                try? await Task.sleep(for: .seconds(max(0, unlockAt.timeIntervalSinceNow)))   // same clock as the ring
                guard !Task.isCancelled, model.isCurrent(id) else { return }
                withAnimation(.spring(duration: 0.6, bounce: 0.3)) { unlocked = true }
                if showsCard, model.prefs.sound { NSSound(named: "Tink")?.play() }
            }
            try? await Task.sleep(for: .seconds(60))
            calm = true
        }
    }

    private var card: some View {
        Group {
            if let result { celebration(result) } else if !unlocked { locked } else { ask }
        }
        .padding(compact ? 22 : 36)
        .frame(width: compact ? 350 : 470)
        .foregroundStyle(.white)
        .background { cardBackground }
        .shadow(color: .black.opacity(0.35), radius: 30, y: 14)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: result?.id)
    }

    private var ask: some View {
        let s = model.stats
        let amounts = model.prefs.checkInAmounts
        let glass = amounts[0], others = Array(amounts.dropFirst())
        return VStack(spacing: compact ? 12 : 18) {
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: compact ? 5 : 7)
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, s.todayFraction)))
                    .stroke(AngularGradient(colors: [Theme.cyan, Theme.aqua, Theme.deepBlue, Theme.cyan], center: .center),
                            style: StrokeStyle(lineWidth: compact ? 5 : 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "drop.fill")
                    .font(.system(size: compact ? 26 : 40, weight: .semibold))
                    .foregroundStyle(Theme.water)
                    .symbolEffect(.breathe, isActive: !calm)
                    .shadow(color: Theme.aqua.opacity(0.6), radius: 12)
            }
            .frame(width: compact ? 62 : 96, height: compact ? 62 : 96)

            VStack(spacing: 6) {
                sipBadge
                Text(line.0).font(.system(size: compact ? 24 : 36, weight: .bold))
                Text(line.1).font(compact ? .callout : .title3).foregroundStyle(.white.opacity(0.7))
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                GeometryReader { g in
                    Capsule().fill(.white.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.cyan, Theme.aqua], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, g.size.width * min(1, s.todayFraction)))
                        }
                }
                .frame(height: 6)
                HStack {
                    Text("\(s.todayML.formatted()) / \(s.todayGoal.formatted()) ml")
                    Spacer()
                    if s.streak > 0 {
                        Label(s.streakAtRisk ? "\(s.streak)-day streak at stake" : "\(s.streak)-day streak",
                              systemImage: "flame.fill")
                            .foregroundStyle(Theme.flame)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
            }

            if captcha {
                // Tick the box (picking an amount first if the bottle offers several).
                // No keyboard shortcut on purpose: it takes a deliberate click.
                CaptchaCheck(ml: pickedML) { drink($0) }
                if !others.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(amounts, id: \.self) { ml in
                            Button("\(ml) ml") { pickedML = ml }
                                .buttonStyle(ChipStyle(on: pickedML == ml))
                                .font(.callout.weight(.semibold))
                        }
                    }
                }
            } else {
                Button { drink(glass) } label: {
                    Label("I drank \(glass) ml", systemImage: "drop.fill")
                        .font(.system(size: compact ? 15 : 17, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryStyle(height: compact ? 44 : 52))
                .keyboardShortcut(armed && !compact ? .defaultAction : nil)

                if !others.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(others, id: \.self) { ml in
                            Button("\(ml) ml") { drink(ml) }
                                .buttonStyle(ChipStyle())
                                .font(.callout.weight(.semibold))
                        }
                    }
                }
            }

            HStack(spacing: 18) {
                Button("Snooze \(model.prefs.snoozeMinutes) min") { model.snooze(id: id) }
                    .keyboardShortcut(armed && !compact && !captcha ? .cancelAction : nil)   // after a lock, only clicks count
                Button("Skip this one") { model.skip(id: id) }
            }
            .buttonStyle(.plain)
            .font(.callout.weight(.medium))
            .foregroundStyle(.white.opacity(0.6))

            if !compact {
                Text(captcha ? "Tick the box once you've had your water" : "Return logs a glass · Esc snoozes")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    /// Liquid Glass greys out in windows that aren't key, and banners never are,
    /// so they get a drawn card that looks the same either way.
    @ViewBuilder private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 26 : 34, style: .continuous)
        if compact {
            shape.fill(Theme.backdrop)
                .overlay(shape.fill(RadialGradient(colors: [Theme.aqua.opacity(0.16), .clear], center: .top,
                                                   startRadius: 0, endRadius: 260)))
                .overlay(shape.strokeBorder(.white.opacity(0.12)))
        } else {
            Color.clear.glassEffect(.regular.tint(Theme.navy.opacity(0.4)), in: shape)
        }
    }

    /// "SIP 3 OF 8 · 219 ML" while a bottle plan is on.
    @ViewBuilder private var sipBadge: some View {
        if model.prefs.bottleOn {
            let plan = model.prefs.bottle
            let next = min(plan.safeSteps, plan.stepsDone(model.stats.todayML) + 1)
            Text("Sip \(next) of \(plan.safeSteps) · \(plan.portionML) ml".uppercased())
                .font(.caption.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.aqua)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.aqua.opacity(0.15)))
        }
    }

    /// The countdown phase: nothing to click except a deliberately slow emergency exit.
    private var locked: some View {
        VStack(spacing: 20) {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                let left = max(0, unlockAt.timeIntervalSince(ctx.date))
                let secs = Int(left.rounded(.up))
                ZStack {
                    Circle().stroke(.white.opacity(0.1), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: left / Double(max(1, lockSeconds)))
                        .stroke(AngularGradient(colors: [Theme.cyan, Theme.aqua, Theme.deepBlue, Theme.cyan],
                                                center: .center),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(secs / 60):\(String(format: "%02d", secs % 60))")
                            .font(.system(size: 44, weight: .heavy))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: secs)
                        Text("until unlock").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.55))
                    }
                }
                .frame(width: 150, height: 150)
            }

            VStack(spacing: 6) {
                sipBadge
                Text("Go drink. Right now.").font(.system(size: 36, weight: .bold))
                Text("Grab a glass of water. This screen unlocks when the timer runs out.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .multilineTextAlignment(.center)

            if model.stats.streakAtRisk {
                Label("\(model.stats.streak)-day streak at stake", systemImage: "flame.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.flame)
            }

            HoldButton(title: "Hold 3 s to snooze (emergency)", seconds: 3) { model.snooze(id: id) }
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private func celebration(_ c: Celebration) -> some View {
        let s = model.stats
        return VStack(spacing: compact ? 10 : 14) {
            PopIcon(
                symbol: c.newLevel != nil ? "star.circle.fill" : c.goalReached ? "trophy.fill" : "checkmark.circle.fill",
                size: compact ? 44 : 66,
                style: c.isBig ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.water))
            Text("+\(c.xp) XP")
                .font(.system(size: compact ? 32 : 48, weight: .heavy))
                .foregroundStyle(Theme.xp)
            if let level = c.newLevel {
                Text("Level \(level) · \(Level.title(level))").font(.title3.bold())
            }
            if c.goalReached {
                Text("Daily goal smashed! 🎉").font(.title3.bold())
            } else if !s.goalMet {
                Text("\(s.remainingML.formatted()) ml to go today").foregroundStyle(.white.opacity(0.7))
            }
            ForEach(c.trophies, id: \.self) { t in
                Label("Unlocked: \(t.title)", systemImage: t.symbol)
                    .font(.callout.bold())
                    .foregroundStyle(Theme.gold)
            }
        }
        .frame(maxWidth: .infinity)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    private func drink(_ ml: Int) {
        guard result == nil, model.isCurrent(id) else { return }   // e.g. a Return during fade-out
        let c = model.log(ml, fromReminder: true)
        result = c
        Task {
            try? await Task.sleep(for: .seconds(c.isBig ? 2.6 : 1.6))
            model.closeReminder(id: id)
        }
    }
}
