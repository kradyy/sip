import Foundation

public enum ReminderStyle: String, Codable, CaseIterable, Sendable {
    case fullscreen, banner
}

/// A bottle you finish over the day in equal steps, e.g. 1750 ml in 8 sips.
public struct BottlePlan: Codable, Equatable, Sendable {
    public var ml: Int
    public var steps: Int
    /// Amount buttons offered when checking in. 1 = just the planned sip.
    public var choices: Int

    public init(ml: Int = 1750, steps: Int = 8, choices: Int = 1) {
        self.ml = ml
        self.steps = steps
        self.choices = choices
    }

    /// Tolerant like `Prefs`: a file saved before a field existed keeps the rest of the bottle.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BottlePlan()
        ml = (try? c.decodeIfPresent(Int.self, forKey: .ml)) ?? d.ml
        steps = (try? c.decodeIfPresent(Int.self, forKey: .steps)) ?? d.steps
        choices = (try? c.decodeIfPresent(Int.self, forKey: .choices)) ?? d.choices
    }

    /// Clamped to sane ranges: always use these, never the raw (possibly hand-edited) values.
    public var safeML: Int { min(max(1, ml), 20_000) }
    public var safeSteps: Int { min(max(1, steps), 48) }
    public var safeChoices: Int { min(max(1, choices), 4) }

    /// Rounded up, so drinking at every step always finishes the bottle (1750 / 8 → 219).
    public var portionML: Int { (safeML + safeSteps - 1) / safeSteps }

    /// Whole steps covered by `ml` drunk today. Drinking the full bottle counts as every step.
    public func stepsDone(_ ml: Int) -> Int {
        ml >= safeML ? safeSteps : min(safeSteps, max(0, ml) / portionML)
    }
}

/// User settings. Decoding tolerates missing or bad keys, so adding a field never wipes saved prefs.
/// Defaults: a 1750 ml bottle in 8 steps between 08:00 and 17:00.
public struct Prefs: Codable, Equatable, Sendable {
    public var intervalMinutes = 45
    public var dailyGoalML = 2500
    public var glassML = 250
    /// Minutes after local midnight. `activeUntil < activeFrom` runs past midnight; equal means all day.
    public var activeFrom = 8 * 60
    public var activeUntil = 17 * 60
    /// While `bottleOn`, the bottle drives the daily goal, the amount per reminder and the interval (see `applyBottle`).
    public var bottle = BottlePlan()
    public var bottleOn = true
    /// No more reminders once today's goal is reached.
    public var quietAfterGoal = true
    /// `Calendar` weekday numbers, 1 = Sunday … 7 = Saturday. Off days never break a streak.
    public var activeWeekdays: Set<Int> = Set(1...7)
    public var snoozeMinutes = 10
    public var style = ReminderStyle.fullscreen
    /// Full-screen reminders stay locked this long (0 = off), so you go drink instead of clicking them away.
    public var lockSeconds = 60
    public var sound = true

    public init() { applyBottle() }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Prefs()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        intervalMinutes = v(.intervalMinutes, d.intervalMinutes)
        dailyGoalML = v(.dailyGoalML, d.dailyGoalML)
        glassML = v(.glassML, d.glassML)
        activeFrom = v(.activeFrom, d.activeFrom)
        activeUntil = v(.activeUntil, d.activeUntil)
        activeWeekdays = v(.activeWeekdays, d.activeWeekdays)
        snoozeMinutes = v(.snoozeMinutes, d.snoozeMinutes)
        style = v(.style, d.style)
        lockSeconds = v(.lockSeconds, d.lockSeconds)
        sound = v(.sound, d.sound)
        bottle = v(.bottle, d.bottle)
        bottleOn = v(.bottleOn, d.bottleOn)
        quietAfterGoal = v(.quietAfterGoal, d.quietAfterGoal)
    }
}

extension Calendar {
    /// Stable "yyyy-MM-dd" key for the local day containing `date`. Locale-independent on purpose.
    public func dayKey(_ date: Date) -> String {
        let c = dateComponents([.year, .month, .day], from: date)
        func pad(_ n: Int?, _ width: Int) -> String {
            let s = String(n ?? 0)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(c.year, 4))-\(pad(c.month, 2))-\(pad(c.day, 2))"
    }
}
