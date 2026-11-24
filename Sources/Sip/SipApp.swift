import AppKit
import ServiceManagement
import SipCore
import SwiftUI

@main
struct SipApp: App {
    private let model = AppModel.shared

    init() {
        // New menu bar icons land far left, where a full bar or the notch hides them. Start near the clock
        // instead (points from the right edge). Only a default: a position the user drags to still wins.
        UserDefaults.standard.register(defaults: ["NSStatusItem Preferred Position Item-0": 300])
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Test hooks for screenshots without clicking the menu bar:
/// `--show-reminder` opens a preview reminder, `--preview-panel today|trophies|settings` opens the
/// panel in a normal window. Visible window ids are printed for `screencapture -l <id>`.
enum DebugHooks {
    private static var windows: [NSWindow] = []

    static func run(_ model: AppModel) {
        let args = CommandLine.arguments
        guard args.contains("--show-reminder") || args.contains("--preview-panel") else { return }
        if args.contains("--show-reminder") { model.showReminder(manual: true) }
        if let i = args.firstIndex(of: "--preview-panel") {
            let name = args.indices.contains(i + 1) ? args[i + 1].lowercased() : ""
            let tab = PanelView.Tab.allCases.first { $0.rawValue.lowercased() == name } ?? .today
            let w = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.contentView = NSHostingView(rootView: PanelView(model: model, tab: tab).clipShape(.rect(cornerRadius: 18)))
            w.center()
            w.orderFrontRegardless()
            windows.append(w)
        }
        for w in NSApp.windows where w.isVisible {
            print("SIP_WINDOW \(w.windowNumber) \(type(of: w)) \(Int(w.frame.width))x\(Int(w.frame.height))")
        }
        fflush(stdout)
    }
}

struct Celebration: Identifiable, Equatable {
    let id = UUID()
    var xp: Int
    var newLevel: Int?
    var goalReached: Bool
    var trophies: [Achievement]
    var isBig: Bool { newLevel != nil || goalReached || !trophies.isEmpty }
}

private struct SavedState: Codable {
    var prefs: Prefs
    var ledger: Ledger
    var reminder: ReminderState

    init(prefs: Prefs, ledger: Ledger, reminder: ReminderState) {
        self.prefs = prefs
        self.ledger = ledger
        self.reminder = reminder
    }

    /// The ledger is the one thing we must not lose; settings and the reminder clock fall back to defaults.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ledger = try c.decode(Ledger.self, forKey: .ledger)
        prefs = (try? c.decodeIfPresent(Prefs.self, forKey: .prefs)) ?? Prefs()
        reminder = (try? c.decodeIfPresent(ReminderState.self, forKey: .reminder)) ?? ReminderState(anchor: Date())
    }
}

@Observable
final class AppModel {
    static let shared = AppModel()

    var prefs: Prefs {
        didSet { if prefs != oldValue { prefsChanged(from: oldValue) } }
    }
    private(set) var ledger: Ledger
    private(set) var reminder: ReminderState
    private(set) var stats = Stats()
    private(set) var nextReminderAt: Date?
    private(set) var reminderVisible = false
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    var celebration: Celebration?

    @ObservationIgnored private let calendar = Calendar.autoupdatingCurrent
    @ObservationIgnored private let storeURL = AppModel.makeStoreURL()
    @ObservationIgnored private let overlay = OverlayController()
    @ObservationIgnored private var reminderID = UUID()
    @ObservationIgnored private var shownAt: Date?
    /// Answering before this earns the on-cue bonus: two minutes, counted from when a lock runs out.
    @ObservationIgnored private var onCueUntil = Date.distantPast
    @ObservationIgnored private var shownIsManual = false
    @ObservationIgnored private var currentDay = ""
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private init() {
        let now = Date()
        if let saved = Self.load(storeURL) {
            var p = saved.prefs
            p.applyBottle()
            prefs = p
            ledger = saved.ledger
            reminder = saved.reminder
            if p.dailyGoalML != saved.prefs.dailyGoalML {
                ledger.goals[calendar.dayKey(now)] = p.dailyGoalML   // the plan changed today's goal
            }
        } else {
            prefs = Prefs()
            ledger = Ledger(startedAt: now)
            reminder = ReminderState(anchor: now)
        }
        recompute(now: now)
        writeNow()

        // Polling beats precise timers here: it survives sleep, clock and timezone changes for free.
        Task {
            while true {
                tick()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { AppModel.shared.writeNow() } }

        Task { DebugHooks.run(self) }
    }

    // MARK: Reminder loop

    private func tick() {
        let now = Date()
        if calendar.dayKey(now) != currentDay { recompute(now: now) } else { refreshNext(now) }

        if reminderVisible {
            // A banner nobody answered turns into a snooze instead of hanging around forever.
            // With snooze off it stays until you drink.
            if prefs.style == .banner, prefs.canSnooze, let shownAt, now.timeIntervalSince(shownAt) > 120 { snooze() }
        } else if let next = nextReminderAt, next <= now {
            showReminder(manual: false)
        }
    }

    func showReminder(manual: Bool) {
        // A real reminder is already up: a preview must not replace it, or its snooze would stop counting.
        if manual, reminderVisible, !shownIsManual { return }
        reminderID = UUID()
        let now = Date()
        shownAt = now
        onCueUntil = prefs.onCueDeadline(shownAt: now)
        shownIsManual = manual
        reminderVisible = overlay.show(style: prefs.style, model: self, id: reminderID)
        if reminderVisible, prefs.sound { NSSound(named: "Glass")?.play() }
    }

    /// Pass the reminder's id from delayed callers, so a stale timer can't close a newer reminder.
    func closeReminder(id: UUID? = nil) {
        if let id, id != reminderID { return }
        overlay.hide()
        reminderVisible = false
        shownAt = nil
    }

    /// True while the reminder with this id is the one on screen.
    func isCurrent(_ id: UUID) -> Bool { reminderVisible && id == reminderID }

    /// Pass the reminder's id from overlay buttons, so a late click on a fading reminder does nothing.
    func snooze(id: UUID? = nil) {
        if let id, !isCurrent(id) { return }
        guard prefs.canSnooze else { return }   // snooze is off: only a drink closes a reminder, previews included
        if !shownIsManual { reminder.snooze(at: Date(), minutes: prefs.snoozeMinutes) }
        closeReminder()
        refreshNext()
        writeNow()
    }

    func skip(id: UUID? = nil) {
        if let id, !isCurrent(id) { return }
        guard prefs.canSnooze else { return }
        if !shownIsManual { reminder.restart(at: Date()) }
        closeReminder()
        refreshNext()
        writeNow()
    }

    /// nil = until tomorrow.
    func pause(minutes: Int?) {
        guard prefs.canSnooze else { return }
        let now = Date()
        reminder.pausedUntil = minutes.map { now.addingTimeInterval(TimeInterval($0 * 60)) }
            ?? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        refreshNext()
        writeNow()
    }

    func resume() {
        reminder.pausedUntil = nil
        refreshNext()
        writeNow()
    }

    var isPaused: Bool { prefs.canSnooze && (reminder.pausedUntil ?? .distantPast) > Date() }

    // MARK: Drinking

    @discardableResult
    func log(_ ml: Int, fromReminder: Bool = false) -> Celebration {
        let now = Date()
        let before = stats
        let onCue = fromReminder && !shownIsManual
            && shownAt != nil && now <= onCueUntil
        if fromReminder { shownAt = nil }   // stops the banner timeout racing the celebration

        ledger.drinks.append(Drink(at: now, ml: ml, onCue: onCue))
        ledger.goals[calendar.dayKey(now)] = prefs.dailyGoalML
        reminder.restart(at: now)
        recompute(now: now)
        writeNow()

        let c = Celebration(
            xp: stats.xp - before.xp,
            newLevel: stats.level > before.level ? stats.level : nil,
            goalReached: stats.goalMet && !before.goalMet,
            trophies: Achievement.allCases.filter { stats.unlocked[$0] != nil && before.unlocked[$0] == nil }
        )
        celebration = c
        if prefs.sound { NSSound(named: c.isBig ? "Hero" : "Pop")?.play() }
        if !fromReminder, reminderVisible { closeReminder() }
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            if celebration?.id == c.id { celebration = nil }
        }
        return c
    }

    var canUndo: Bool { ledger.drinks.last.map { calendar.isDateInToday($0.at) } ?? false }

    func undoLast() {
        guard canUndo else { return }
        ledger.drinks.removeLast()
        recompute(now: Date())
        writeNow()
    }

    func resetProgress() {
        let now = Date()
        ledger = Ledger(startedAt: now)
        reminder = ReminderState(anchor: now, pausedUntil: reminder.pausedUntil)
        recompute(now: now)
        writeNow()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Sip: launch at login failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func quit() {
        writeNow()
        NSApp.terminate(nil)
    }

    // MARK: Derived state

    private func prefsChanged(from old: Prefs) {
        // Keep goal, sip size and interval in step with the bottle plan (re-enters once with derived values).
        var derived = prefs
        derived.applyBottle()
        if derived != prefs {
            prefs = derived
            return
        }
        if prefs.dailyGoalML != old.dailyGoalML {
            ledger.goals[calendar.dayKey(Date())] = prefs.dailyGoalML
        }
        recompute(now: Date())
        save()
    }

    private func recompute(now: Date) {
        currentDay = calendar.dayKey(now)
        // Pin each day's goal the first time we see it, so a later goal change never rewrites history.
        if ledger.goals[currentDay] == nil {
            ledger.goals[currentDay] = prefs.dailyGoalML
            save()
        }
        stats = Progression.compute(ledger: ledger, prefs: prefs, now: now, calendar: calendar)
        refreshNext(now)
    }

    private func refreshNext(_ now: Date = Date()) {
        let next = prefs.nextReminder(reminder, now: now, calendar: calendar, goalMet: stats.goalMet)
        if next != nextReminderAt { nextReminderAt = next }
    }

    // MARK: Persistence

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static func makeStoreURL() -> URL {
        if let dir = ProcessInfo.processInfo.environment["SIP_STATE_DIR"] {
            return URL(filePath: dir, directoryHint: .isDirectory).appending(path: "state.json")
        }
        return URL.applicationSupportDirectory.appending(path: "Sip/state.json")
    }

    /// Set when an existing state file could neither be read nor moved aside: saving is then
    /// switched off for this run, so the original file survives untouched.
    private static var storeLocked = false

    private static func load(_ url: URL) -> SavedState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try decoder.decode(SavedState.self, from: Data(contentsOf: url))
        } catch {
            // Never overwrite someone's history: move the unreadable file aside first.
            let backup = url.deletingLastPathComponent()
                .appending(path: "state-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            do {
                try FileManager.default.moveItem(at: url, to: backup)
                NSLog("Sip: state unreadable (\(error)); moved to \(backup.path)")
            } catch {
                storeLocked = true
                NSLog("Sip: state unreadable and can't be moved; not saving this session: \(error)")
            }
            return nil
        }
    }

    func writeNow() {
        saveTask?.cancel()
        guard !Self.storeLocked else { return }
        let state = SavedState(prefs: prefs, ledger: ledger, reminder: reminder)
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(state).write(to: storeURL, options: .atomic)
        } catch {
            NSLog("Sip: save failed: \(error.localizedDescription)")
        }
    }

    /// Debounced: sliders fire many changes per second.
    private func save() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { writeNow() }
        }
    }
}
