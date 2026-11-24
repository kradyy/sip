import Foundation

/// Where the reminder clock stands. Every drink restarts the interval, so you're never nagged right after drinking.
public struct ReminderState: Codable, Equatable, Sendable {
    /// Start of the current interval: last drink, skip, or first launch.
    public var anchor: Date
    public var snoozedUntil: Date?
    public var pausedUntil: Date?

    public init(anchor: Date, snoozedUntil: Date? = nil, pausedUntil: Date? = nil) {
        self.anchor = anchor
        self.snoozedUntil = snoozedUntil
        self.pausedUntil = pausedUntil
    }

    /// A drink or a skip: start a fresh interval and drop any snooze. A pause stays in place.
    public mutating func restart(at now: Date) {
        anchor = now
        snoozedUntil = nil
    }

    public mutating func snooze(at now: Date, minutes: Int) {
        snoozedUntil = now.addingTimeInterval(minutesToSeconds(minutes))
    }
}

/// Clamped and computed in floating point, so a corrupt prefs file (e.g. `Int.max`) can't trap the app.
func minutesToSeconds(_ minutes: Int) -> TimeInterval {
    TimeInterval(min(max(1, minutes), 100_000_000)) * 60
}

extension Prefs {
    private static func clampMinute(_ m: Int) -> Int { ((m % 1440) + 1440) % 1440 }

    /// The active window that opens on the local day of `day`, or nil when that weekday is off.
    /// Wall-clock based, so DST days still open at 08:00, not "midnight + 8h".
    public func window(on day: Date, calendar cal: Calendar) -> DateInterval? {
        let dayStart = cal.startOfDay(for: day)
        guard activeWeekdays.contains(cal.component(.weekday, from: dayStart)) else { return nil }
        let from = Self.clampMinute(activeFrom), until = Self.clampMinute(activeUntil)
        guard
            let start = cal.date(bySettingHour: from / 60, minute: from % 60, second: 0, of: dayStart),
            let endDay = until > from ? dayStart : cal.date(byAdding: .day, value: 1, to: dayStart),
            let end = cal.date(bySettingHour: until / 60, minute: until % 60, second: 0, of: endDay),
            end > start
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Earliest instant ≥ `t` inside an active window. nil only when no weekday is enabled.
    public func nextActiveInstant(atOrAfter t: Date, calendar cal: Calendar) -> Date? {
        guard !activeWeekdays.isEmpty else { return nil }
        let today = cal.startOfDay(for: t)
        // Yesterday's window may run past midnight into today; a week ahead always finds an enabled day.
        for offset in -1...8 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  let w = window(on: day, calendar: cal) else { continue }
            if t < w.end { return max(t, w.start) }
        }
        return nil
    }

    /// Length of the daily active window in minutes (1440 = all day).
    public var activeMinutes: Int {
        let from = Self.clampMinute(activeFrom), until = Self.clampMinute(activeUntil)
        return until == from ? 1440 : (until - from + 1440) % 1440
    }

    /// Derives goal, amount per reminder and interval from the bottle. The interval is rounded up so
    /// exactly `steps` reminders fit the window: 1750 ml / 8 over 08:00–17:00 → 219 ml every 68 min.
    /// A glass size the user picked replaces the sip amount.
    public mutating func applyBottle() {
        guard bottleOn else { return }
        dailyGoalML = bottle.safeML
        glassML = bottle.glassML
        intervalMinutes = max(5, Int((Double(activeMinutes) / Double(bottle.safeSteps)).rounded(.up)))
    }

    /// Amounts offered when checking in, the planned glass first. A bottle plan caps the list at `bottle.choices`.
    public var checkInAmounts: [Int] {
        let all = [glassML] + [150, 330, 500].filter { $0 != glassML }
        return Array(all.prefix(bottleOn ? bottle.safeChoices : all.count))
    }

    /// Snooze set to Off (0 minutes): no snooze, skip or pause. Only a drink closes a reminder, previews included.
    public var canSnooze: Bool { snoozeMinutes > 0 }

    /// How long a reminder stays locked: full-screen only, capped at 10 minutes.
    public var effectiveLockSeconds: Int { style == .fullscreen ? min(max(0, lockSeconds), 600) : 0 }

    /// Last moment a drink still earns the on-cue bonus for a reminder shown at `shownAt`.
    /// The answer window starts once the lock runs out, so a long lock never costs the bonus.
    public func onCueDeadline(shownAt: Date) -> Date {
        shownAt.addingTimeInterval(TimeInterval(effectiveLockSeconds) + Rules.onCueWindow)
    }

    public func isActive(at t: Date, calendar cal: Calendar) -> Bool {
        nextActiveInstant(atOrAfter: t, calendar: cal) == t
    }

    /// When the next reminder fires, never earlier than `now`. A result equal to `now` means "fire now".
    /// Overdue reminders (Mac asleep, app closed) fire once, but only inside an active window.
    /// With `goalMet` and `quietAfterGoal`, the rest of today stays quiet.
    public func nextReminder(_ state: ReminderState, now: Date, calendar cal: Calendar, goalMet: Bool = false) -> Date? {
        var due = state.snoozedUntil
            ?? state.anchor.addingTimeInterval(minutesToSeconds(intervalMinutes))
        // A pause set before Snooze was turned Off doesn't count.
        if canSnooze, let paused = state.pausedUntil, paused > due { due = paused }
        if goalMet, quietAfterGoal,
           let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)), tomorrow > due {
            due = tomorrow
        }
        return nextActiveInstant(atOrAfter: max(due, now), calendar: cal)
    }
}
