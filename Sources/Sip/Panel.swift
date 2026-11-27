import Charts
import SipCore
import SwiftUI

struct PanelView: View {
    let model: AppModel
    @State private var tab: Tab
    @State private var onScreen = false

    enum Tab: String, CaseIterable { case today = "Today", trophies = "Trophies", settings = "Settings" }

    init(model: AppModel, tab: Tab = .today) {
        self.model = model
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            TabBar(tab: $tab)
            Group {
                switch tab {
                case .today: TodayTab(model: model)
                case .trophies: TrophiesTab(model: model)
                case .settings: SettingsTab(model: model)
                }
            }
            .frame(height: 560, alignment: .top)   // fixed so switching tabs never resizes the panel
        }
        .padding(16)
        .frame(width: 360)
        .background {
            ZStack {
                Theme.backdrop
                RadialGradient(colors: [Theme.aqua.opacity(0.18), .clear], center: .top, startRadius: 0, endRadius: 320)
            }
        }
        .overlay {
            if let c = model.celebration { Burst(power: 0.7).id(c.id) }
        }
        .overlay(alignment: .top) {
            if let c = model.celebration { Toast(c: c).padding(.top, 10) }
        }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: model.celebration?.id)
        // MenuBarExtra keeps its window alive while closed; these fire on every open and close.
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .environment(\.liveAnimations, onScreen)
        .preferredColorScheme(.dark)
        .fontDesign(.rounded)
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "drop.fill")
                .font(.title2)
                .foregroundStyle(Theme.water)
            Text("Sip").font(.title2.weight(.heavy))
            Spacer()
            Text("Lv \(model.stats.level) · \(model.stats.title)")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Theme.xp.opacity(0.35)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
            Button { model.quit() } label: {
                Image(systemName: "power").font(.callout.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.5))
            .help("Quit Sip")
        }
    }
}

private struct Toast: View {
    let c: Celebration

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: c.isBig ? "sparkles" : "drop.fill")
            Text("+\(c.xp) XP")
            if let level = c.newLevel { Text("· Level \(level)!") }
            if c.goalReached { Text("· Goal hit!") }
            if let t = c.trophies.first { Text("· \(t.title)") }
        }
        .font(.callout.bold())
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(c.isBig ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Theme.water)))
        .foregroundStyle(c.isBig ? .black : .white)
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

private struct TabBar: View {
    @Binding var tab: PanelView.Tab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PanelView.Tab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.spring(duration: 0.35)) { tab = t }
                } label: {
                    Text(t.rawValue)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(tab == t ? .white : .white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if tab == t {
                                Capsule().fill(.white.opacity(0.14)).matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(.white.opacity(0.06)))
    }
}

// MARK: Today

private struct TodayTab: View {
    let model: AppModel

    var body: some View {
        let s = model.stats
        VStack(spacing: 14) {
            ZStack {
                Bottle(fraction: s.todayFraction, steps: model.prefs.bottleOn ? model.prefs.bottle.safeSteps : 0)
                    .frame(width: 190, height: 190)
                VStack(spacing: 0) {
                    Text(s.todayML.formatted())
                        .font(.system(size: 40, weight: .bold))
                        .contentTransition(.numericText(value: Double(s.todayML)))
                    Text("of \(s.todayGoal.formatted()) ml")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                    if model.prefs.bottleOn {
                        SipDots(plan: model.prefs.bottle, ml: s.todayML).padding(.top, 6)
                    } else if s.goalMet {
                        Label("Goal hit", systemImage: "checkmark.seal.fill")
                            .font(.caption.bold())
                            .padding(.top, 4)
                    }
                }
                .shadow(color: .black.opacity(0.35), radius: 6)
            }
            .animation(.spring(duration: 0.6), value: s.todayML)

            VStack(spacing: 5) {
                HStack {
                    Text("Level \(s.level)").fontWeight(.bold)
                    Text(s.title).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("\(s.xp - s.levelFloorXP) / \(s.nextLevelXP - s.levelFloorXP) XP")
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                }
                .font(.caption)
                GeometryReader { g in
                    Capsule().fill(.white.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.xp).frame(width: max(6, g.size.width * s.levelFraction))
                        }
                }
                .frame(height: 6)
                .animation(.spring(duration: 0.8), value: s.xp)
            }

            HStack(spacing: 8) {
                StatPill(symbol: "flame.fill", tint: Theme.flame, value: "\(s.streak)",
                         caption: s.streakAtRisk ? "streak at risk" : "day streak")
                StatPill(symbol: "snowflake", tint: Theme.ice, value: "\(s.freezes)", caption: "freezes")
                StatPill(symbol: "trophy.fill", tint: Theme.gold, value: "\(s.unlocked.count)", caption: "trophies")
            }

            QuickAdd(model: model)
            NextReminder(model: model)
            WeekChart(week: s.week, goal: s.todayGoal)
        }
    }
}

private struct StatPill: View {
    let symbol: String
    let tint: Color
    let value: String
    let caption: String

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(value)
                    .font(.title3.weight(.bold))
                    .contentTransition(.numericText())
            }
            Text(caption).font(.caption2).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.06)))
    }
}

private struct QuickAdd: View {
    let model: AppModel

    var body: some View {
        let amounts = model.prefs.checkInAmounts.prefix(3)
        HStack(spacing: 8) {
            ForEach(Array(amounts.enumerated()), id: \.offset) { i, ml in
                Button { model.log(ml) } label: {
                    VStack(spacing: 1) {
                        Image(systemName: i == 0 ? "cup.and.saucer.fill" : "plus")
                            .font(.caption.weight(.bold))
                        Text("\(ml) ml").font(.callout.weight(.semibold))
                    }
                }
                .buttonStyle(ChipStyle(on: i == 0))
            }
            Button { model.undoLast() } label: {
                Image(systemName: "arrow.uturn.backward").font(.callout.weight(.semibold))
            }
            .buttonStyle(ChipStyle())
            .frame(width: 48)
            .disabled(!model.canUndo)
            .opacity(model.canUndo ? 1 : 0.4)
            .help("Undo last drink")
        }
    }
}

private struct NextReminder: View {
    let model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { ctx in
            HStack(spacing: 10) {
                let call = model.holdingForCall && !model.isPaused
                Image(systemName: model.isPaused ? "pause.circle.fill" : call ? "video.circle.fill" : "bell.badge.fill")
                    .font(.title2)
                    .foregroundStyle(model.isPaused ? AnyShapeStyle(.white.opacity(0.6)) : AnyShapeStyle(Theme.water))
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.isPaused ? "Paused" : call ? "On a call · reminders wait" : "Next reminder")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                    Text(call && (model.nextReminderAt ?? .distantFuture) <= ctx.date.addingTimeInterval(45)
                         ? "Right after your call" : Self.describe(model.nextReminderAt, now: ctx.date))
                        .font(.callout.weight(.semibold))
                }
                Spacer()
                Menu {
                    if model.isPaused {
                        Button("Resume reminders") { model.resume() }
                        Divider()
                    } else if model.prefs.canSnooze {
                        Button("Pause for 1 hour") { model.pause(minutes: 60) }
                        Button("Pause for 3 hours") { model.pause(minutes: 180) }
                        Button("Pause until tomorrow") { model.pause(minutes: nil) }
                        Divider()
                    }
                    Button("Remind me now") { model.showReminder(manual: true) }
                } label: {
                    Image(systemName: "ellipsis.circle.fill").font(.title2)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.white.opacity(0.7))
            }
            .card(padding: 10)
        }
    }

    static func describe(_ next: Date?, now: Date) -> String {
        guard let next else { return "Off — no active days" }
        let secs = next.timeIntervalSince(now)
        if secs < 45 { return "Any second now" }
        if secs < 3600 { return "In \(Int((secs / 60).rounded())) min" }
        let time = next.formatted(date: .omitted, time: .shortened)
        let cal = Calendar.current
        if cal.isDate(next, inSameDayAs: now) { return "Today at \(time)" }
        if cal.isDateInTomorrow(next) { return "Tomorrow at \(time)" }
        return "\(next.formatted(.dateTime.weekday(.wide))) at \(time)"
    }
}

private struct WeekChart: View {
    let week: [DayTotal]
    let goal: Int

    var body: some View {
        Chart {
            ForEach(week) { d in
                BarMark(x: .value("Day", d.day, unit: .day), y: .value("ml", d.ml))
                    .foregroundStyle(d.met ? AnyShapeStyle(Theme.water) : AnyShapeStyle(.white.opacity(0.22)))
                    .cornerRadius(5)
            }
            RuleMark(y: .value("Goal", goal))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.white.opacity(0.35))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...max(goal, week.map(\.ml).max() ?? 0))
        .frame(height: 104)
        .card(padding: 10)
    }
}

// MARK: Trophies

private struct TrophiesTab: View {
    let model: AppModel

    var body: some View {
        let s = model.stats
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.08), lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: s.levelFraction)
                            .stroke(Theme.xp, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: -2) {
                            Text("LV").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.6))
                            Text("\(s.level)").font(.system(size: 28, weight: .heavy))
                        }
                    }
                    .frame(width: 74, height: 74)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.title).font(.title2.weight(.heavy))
                        Text("\(s.xp.formatted()) XP total").font(.callout).foregroundStyle(.white.opacity(0.7))
                        Text("\((s.nextLevelXP - s.xp).formatted()) XP to \(Level.title(s.level + 1))")
                            .font(.caption).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                }
                .card()

                HStack(spacing: 8) {
                    Lifetime(value: String(format: "%.1f L", Double(s.totalML) / 1000), caption: "lifetime")
                    Lifetime(value: "\(s.totalDrinks)", caption: "drinks")
                    Lifetime(value: "\(s.bestStreak)", caption: "best streak")
                    Lifetime(value: "\(s.onCueCount)", caption: "on cue")
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Achievement.allCases, id: \.self) { a in
                        TrophyCell(achievement: a, unlockedAt: s.unlocked[a])
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .scrollFade()
    }
}

private struct Lifetime: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.callout.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05)))
    }
}

private struct TrophyCell: View {
    let achievement: Achievement
    let unlockedAt: Date?

    var body: some View {
        let on = unlockedAt != nil
        VStack(spacing: 5) {
            ZStack {
                Circle().fill(on ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(.white.opacity(0.06)))
                Image(systemName: on ? achievement.symbol : "lock.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(on ? .black.opacity(0.7) : .white.opacity(0.3))
            }
            .frame(width: 42, height: 42)
            .shadow(color: on ? Theme.gold.opacity(0.45) : .clear, radius: 8)
            Text(achievement.title).font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8)
            Text(achievement.detail)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(on ? 0.08 : 0.03)))
        .help(on ? "\(achievement.detail) · +\(achievement.xp) XP · unlocked \(unlockedAt!.formatted(date: .abbreviated, time: .omitted))"
                 : "\(achievement.detail) · +\(achievement.xp) XP")
    }
}

// MARK: Settings

private struct SettingsTab: View {
    @Bindable var model: AppModel
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Section("Bottle plan") {
                    Switch("Drink by bottle", isOn: $model.prefs.bottleOn)
                    if model.prefs.bottleOn {
                        HStack {
                            Text("Bottle size")
                            Spacer()
                            Text(liters(model.prefs.bottle.ml)).monospacedDigit().fontWeight(.semibold)
                            Stepper("", value: $model.prefs.bottle.ml, in: 250...5000, step: 50).labelsHidden()
                        }
                        HStack {
                            Text("Sips per day")
                            Spacer()
                            Text("\(model.prefs.bottle.steps)").monospacedDigit().fontWeight(.semibold)
                            Stepper("", value: $model.prefs.bottle.steps, in: 1...24).labelsHidden()
                        }
                        HStack {
                            Text("Check-in buttons")
                            Spacer()
                            Text("\(model.prefs.bottle.safeChoices)").monospacedDigit().fontWeight(.semibold)
                            Stepper("", value: $model.prefs.bottle.choices, in: 1...4).labelsHidden()
                        }
                        Text("\(model.prefs.bottle.portionML) ml per sip · a reminder every \(model.prefs.intervalMinutes) min within your active hours · \(model.prefs.bottle.safeChoices == 1 ? "one tap to check in" : "\(model.prefs.bottle.safeChoices) amounts to pick from")")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }

                Section("Reminders") {
                    Row("Remind every", "\(model.prefs.intervalMinutes) min") {
                        Slider(value: Binding(
                            get: { Double(model.prefs.intervalMinutes) },
                            set: { model.prefs.intervalMinutes = Int(($0 / 5).rounded()) * 5 }), in: 5...180)
                            .disabled(model.prefs.bottleOn)
                    }
                    HStack {
                        Text("Style")
                        Spacer()
                        Picker("", selection: $model.prefs.style) {
                            Text("Full screen").tag(ReminderStyle.fullscreen)
                            Text("Banner").tag(ReminderStyle.banner)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    if model.prefs.style == .fullscreen {
                        HStack {
                            Text("Lock screen for")
                            Spacer()
                            Picker("", selection: $model.prefs.lockSeconds) {
                                ForEach(options([0, 15, 30, 60, 120, 300], model.prefs.lockSeconds), id: \.self) { s in
                                    Text(s == 0 ? "Off" : s < 60 ? "\(s) s" : "\(s / 60) min").tag(s)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        .help("The reminder can't be closed until this runs out, so you actually go drink.")
                    }
                    HStack {
                        Text("Snooze for")
                        Spacer()
                        Picker("", selection: $model.prefs.snoozeMinutes) {
                            ForEach(options([0, 5, 10, 15, 30], model.prefs.snoozeMinutes), id: \.self) {
                                Text($0 <= 0 ? "Off" : "\($0) min").tag($0)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    if !model.prefs.canSnooze {
                        Text("No snooze, skip or pause: the only way past a reminder is drinking.")
                            .font(.caption).foregroundStyle(.white.opacity(0.5))
                    }
                    Switch("Quiet once goal is hit", isOn: $model.prefs.quietAfterGoal)
                    Switch("Hold reminders during calls", isOn: $model.prefs.holdDuringCalls)
                        .help("While your camera or microphone is in use, reminders wait and show a minute after the call.")
                    Switch("Sounds", isOn: $model.prefs.sound)
                }

                Section("Goal") {
                    HStack {
                        Text("Daily goal")
                        Spacer()
                        Text(liters(model.prefs.dailyGoalML))
                            .monospacedDigit().fontWeight(.semibold)
                        if model.prefs.bottleOn {
                            Stepper("", value: $model.prefs.bottle.ml, in: 250...5000, step: 50).labelsHidden()
                        } else {
                            Stepper("", value: $model.prefs.dailyGoalML, in: 500...6000, step: 100).labelsHidden()
                        }
                    }
                    HStack {
                        Text("Glass size")
                        Spacer()
                        Picker("", selection: glassSize) {
                            let sip = model.prefs.bottleOn ? [model.prefs.bottle.portionML] : []
                            ForEach(options([150, 200, 250, 300, 330, 400, 500] + sip, model.prefs.glassML), id: \.self) { ml in
                                Text(sip.contains(ml) ? "\(ml) ml · one sip" : "\(ml) ml").tag(ml)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    if model.prefs.bottleOn {
                        Text("Your daily goal is the bottle. A reminder logs one glass.")
                            .font(.caption).foregroundStyle(.white.opacity(0.5))
                    }
                }

                Section("Active hours") {
                    HStack {
                        DatePicker("", selection: time(\.activeFrom), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text("to").foregroundStyle(.white.opacity(0.6))
                        DatePicker("", selection: time(\.activeUntil), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Spacer()
                    }
                    WeekdayPicker(days: $model.prefs.activeWeekdays)
                        .help("Off days never break your streak")
                }

                Section("General") {
                    Switch("Launch at login", isOn: Binding(
                        get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    HStack(spacing: 8) {
                        Button("Preview reminder") { model.showReminder(manual: true) }
                        Spacer()
                        Button(confirmReset ? "Really reset?" : "Reset progress") {
                            if confirmReset {
                                model.resetProgress()
                                confirmReset = false
                            } else {
                                confirmReset = true
                                Task {
                                    try? await Task.sleep(for: .seconds(4))
                                    confirmReset = false
                                }
                            }
                        }
                        .tint(confirmReset ? .red : nil)
                    }
                }
            }
            .font(.callout)
            .padding(.bottom, 20)
        }
        .scrollFade()
    }

    /// Keeps a hand-edited value selectable instead of showing a blank picker.
    /// With a bottle plan, picking the sip size goes back to automatic, so later bottle changes keep it in step.
    private var glassSize: Binding<Int> {
        Binding(
            get: { model.prefs.glassML },
            set: { ml in
                if model.prefs.bottleOn {
                    model.prefs.bottle.customGlassML = ml == model.prefs.bottle.portionML ? nil : ml
                } else {
                    model.prefs.glassML = ml
                }
            })
    }

    private func options(_ base: [Int], _ current: Int) -> [Int] {
        Set(base + [current]).sorted()
    }

    private func time(_ key: WritableKeyPath<Prefs, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = model.prefs[keyPath: key]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                model.prefs[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }
}

/// "1.75 L", "2 L".
private func liters(_ ml: Int) -> String {
    (Double(ml) / 1000).formatted(.number.precision(.fractionLength(0...2))) + " L"
}

/// One dot per sip of the bottle plan; falls back to text when there are too many to draw.
private struct SipDots: View {
    let plan: BottlePlan
    let ml: Int

    var body: some View {
        let done = plan.stepsDone(ml)
        VStack(spacing: 4) {
            if plan.safeSteps <= 12 {
                HStack(spacing: 4) {
                    ForEach(0..<plan.safeSteps, id: \.self) { i in
                        Capsule()
                            .fill(i < done ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.28)))
                            .frame(width: 10, height: 4)
                    }
                }
            }
            Text(done >= plan.safeSteps ? "Bottle finished 🎉" : "\(done) / \(plan.safeSteps) sips")
                .font(.caption.weight(.bold))
        }
        .animation(.spring(duration: 0.5), value: done)
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.45))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct Row<Control: View>: View {
    let title: String
    var value: String?
    @ViewBuilder let control: Control

    init(_ title: String, _ value: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.value = value
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                if let value { Text(value).monospacedDigit().fontWeight(.semibold) }
            }
            control
        }
    }
}

private struct Switch: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Theme.deepBlue)
        }
    }
}

private struct WeekdayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        let cal = Calendar.current
        let symbols = cal.shortWeekdaySymbols.map { String($0.prefix(2)).capitalized }
        let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 + 1 }
        HStack(spacing: 5) {
            ForEach(order, id: \.self) { wd in
                Button(symbols[wd - 1]) {
                    if days.contains(wd) { days.remove(wd) } else { days.insert(wd) }
                }
                .buttonStyle(ChipStyle(on: days.contains(wd)))
                .font(.caption.weight(.bold))
            }
        }
    }
}
