import Foundation

public struct Drink: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var at: Date
    public var ml: Int
    /// Logged straight from a reminder, within `Rules.onCueWindow` of its lock running out (see `Prefs.onCueDeadline`).
    public var onCue: Bool

    public init(id: UUID = UUID(), at: Date, ml: Int, onCue: Bool = false) {
        self.id = id
        self.at = at
        self.ml = ml
        self.onCue = onCue
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        at = try c.decode(Date.self, forKey: .at)
        ml = try c.decode(Int.self, forKey: .ml)
        onCue = (try? c.decodeIfPresent(Bool.self, forKey: .onCue)) ?? false
    }
}

/// Everything the user did. All XP, levels, streaks and trophies are *derived* from this,
/// so undoing a drink or fixing a clock can never leave progress in a stale state.
public struct Ledger: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var drinks: [Drink]
    /// Goal in effect per day key. Days without an entry inherit the previous recorded goal.
    public var goals: [String: Int]

    public init(startedAt: Date, drinks: [Drink] = [], goals: [String: Int] = [:]) {
        self.startedAt = startedAt
        self.drinks = drinks
        self.goals = goals
    }

    /// Only the drinks are essential; a missing start date or goal history is rebuilt,
    /// and a single malformed drink is dropped instead of costing the whole history.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        drinks = try c.decodeIfPresent([LossyDrink].self, forKey: .drinks)?.compactMap(\.drink) ?? []
        startedAt = (try? c.decodeIfPresent(Date.self, forKey: .startedAt)) ?? drinks.map(\.at).min() ?? Date()
        goals = (try? c.decodeIfPresent([String: Int].self, forKey: .goals)) ?? [:]
    }
}

private struct LossyDrink: Decodable {
    let drink: Drink?
    init(from decoder: any Decoder) throws { drink = try? Drink(from: decoder) }
}

public enum Rules {
    public static let mlPerXP = 25               // 250 ml glass = 10 XP
    public static let volumeCapPercent = 150     // volume XP stops at 150% of the day's goal
    public static let onCueXP = 5
    public static let onCueWindow: TimeInterval = 120
    public static let goalXP = 50
    public static let streakXPPerDay = 5         // goal day bonus = 5 × streak length …
    public static let streakXPMaxDays = 20       // … capped at a 20-day streak (+100)
    public static let freezeEvery = 7            // every 7 streak days earns a freeze
    public static let maxFreezes = 2
    public static let earlyBirdHours = 5..<8
    public static let maxGoalML = 1_000_000
    public static let maxDrinkML = 100_000
    public static let historyLimitDays = 3650
}

public enum Achievement: String, CaseIterable, Codable, Sendable {
    case firstSip, goalGetter, hatTrick, weekWarrior, fortnight, monsoon
    case overflow, earlyBird, quickDraw, reflexes, tenLiters, centurion, comeback

    public var title: String {
        switch self {
        case .firstSip: "First Sip"
        case .goalGetter: "Goal Getter"
        case .hatTrick: "Hat Trick"
        case .weekWarrior: "Week Warrior"
        case .fortnight: "Fortnight Flow"
        case .monsoon: "Monsoon"
        case .overflow: "Overflow"
        case .earlyBird: "Early Bird"
        case .quickDraw: "Quick Draw"
        case .reflexes: "Reflexes"
        case .tenLiters: "Ten Liters"
        case .centurion: "Centurion"
        case .comeback: "Comeback Kid"
        }
    }

    public var detail: String {
        switch self {
        case .firstSip: "Log your very first drink"
        case .goalGetter: "Hit your daily goal"
        case .hatTrick: "3-day streak"
        case .weekWarrior: "7-day streak"
        case .fortnight: "14-day streak"
        case .monsoon: "30-day streak"
        case .overflow: "150% of your goal in one day"
        case .earlyBird: "A drink between 5:00 and 8:00"
        case .quickDraw: "Answer 10 reminders fast"
        case .reflexes: "Answer 100 reminders fast"
        case .tenLiters: "Drink 10 liters in total"
        case .centurion: "Log 100 drinks"
        case .comeback: "Bounce back after losing a 3+ day streak"
        }
    }

    public var symbol: String {
        switch self {
        case .firstSip: "drop.fill"
        case .goalGetter: "target"
        case .hatTrick: "flame.fill"
        case .weekWarrior: "calendar"
        case .fortnight: "medal.fill"
        case .monsoon: "cloud.heavyrain.fill"
        case .overflow: "water.waves"
        case .earlyBird: "sunrise.fill"
        case .quickDraw: "bolt.fill"
        case .reflexes: "bolt.circle.fill"
        case .tenLiters: "waterbottle.fill"
        case .centurion: "rosette"
        case .comeback: "arrow.counterclockwise.circle.fill"
        }
    }

    public var xp: Int {
        switch self {
        case .firstSip: 25
        case .goalGetter, .quickDraw: 50
        case .hatTrick, .overflow, .earlyBird, .comeback: 75
        case .tenLiters: 100
        case .weekWarrior, .centurion: 150
        case .fortnight, .reflexes: 250
        case .monsoon: 500
        }
    }
}

public enum Level {
    /// Total XP needed to reach `level`: 1 → 0, 2 → 100, 3 → 300, 4 → 600, …
    public static func threshold(_ level: Int) -> Int {
        let n = max(1, level)
        return 50 * n * (n - 1)
    }

    public static func level(forXP xp: Int) -> Int {
        let xp = max(0, xp)
        // Closed form of 50·n·(n−1) ≤ xp, then nudge to absorb floating-point error.
        var n = max(1, Int((1 + (1 + Double(xp) / 12.5).squareRoot()) / 2))
        while threshold(n + 1) <= xp { n += 1 }
        while n > 1, threshold(n) > xp { n -= 1 }
        return n
    }

    public static let titles = [
        "Dry Sponge", "Droplet", "Puddle", "Rain Shower", "Brook", "Stream", "River",
        "Lake", "Waterfall", "Glacier", "Sea", "Ocean", "Tidal Wave", "Poseidon",
    ]

    public static func title(_ level: Int) -> String {
        titles[min(max(level, 1), titles.count) - 1]
    }
}

public struct DayTotal: Equatable, Identifiable, Sendable {
    public var day: Date
    public var ml: Int
    public var goal: Int
    public var id: Date { day }
    public var met: Bool { goal > 0 && ml >= goal }
}

public struct Stats: Equatable, Sendable {
    public var xp = 0
    public var todayML = 0
    public var todayGoal = 0
    /// Consecutive goal days. Includes today once today's goal is met.
    public var streak = 0
    public var bestStreak = 0
    /// Streak > 0, today is an active day and today's goal isn't met yet.
    public var streakAtRisk = false
    public var freezes = 0
    public var totalML = 0
    public var totalDrinks = 0
    public var onCueCount = 0
    public var unlocked: [Achievement: Date] = [:]
    /// Last 7 days, oldest first, ending today.
    public var week: [DayTotal] = []

    public init() {}

    public var level: Int { Level.level(forXP: xp) }
    public var title: String { Level.title(level) }
    public var levelFloorXP: Int { Level.threshold(level) }
    public var nextLevelXP: Int { Level.threshold(level + 1) }
    public var levelFraction: Double {
        Double(xp - levelFloorXP) / Double(max(1, nextLevelXP - levelFloorXP))
    }
    public var todayFraction: Double { Double(todayML) / Double(max(1, todayGoal)) }
    public var goalMet: Bool { todayGoal > 0 && todayML >= todayGoal }
    public var remainingML: Int { max(0, todayGoal - todayML) }
}

public enum Progression {
    /// Replays the whole ledger day by day. Deterministic: same ledger + prefs + now → same stats.
    public static func compute(ledger: Ledger, prefs: Prefs, now: Date, calendar cal: Calendar) -> Stats {
        let drinks = ledger.drinks
            .filter { $0.at <= now && $0.ml > 0 }
            .map { d in var d = d; d.ml = min(d.ml, Rules.maxDrinkML); return d }   // absurd input can't overflow
            .sorted { $0.at < $1.at }
        let byDay = Dictionary(grouping: drinks) { cal.dayKey($0.at) }

        let today = cal.startOfDay(for: now)
        let todayKey = cal.dayKey(now)
        let earliest = min(ledger.startedAt, drinks.first?.at ?? ledger.startedAt)
        let floor = cal.date(byAdding: .day, value: -Rules.historyLimitDays, to: today) ?? today
        var day = cal.startOfDay(for: max(earliest, floor))

        var s = Stats()
        var goal = ledger.goals.min { $0.key < $1.key }?.value ?? prefs.dailyGoalML
        var goalByDay: [String: Int] = [:]
        var lostStreak = 0

        func unlock(_ a: Achievement, _ at: Date) {
            guard s.unlocked[a] == nil else { return }
            s.unlocked[a] = at
            s.xp += a.xp
        }

        while day <= today {
            let key = cal.dayKey(day)
            let isToday = key == todayKey
            goal = min(Rules.maxGoalML, max(1, isToday ? prefs.dailyGoalML : (ledger.goals[key] ?? goal)))
            goalByDay[key] = goal

            let dayDrinks = byDay[key] ?? []
            let total = dayDrinks.reduce(0) { $0 + $1.ml }
            s.xp += min(total, goal * Rules.volumeCapPercent / 100) / Rules.mlPerXP

            // Goal trophies are stamped with the drink that actually crossed the line.
            var running = 0
            var goalAt: Date?
            var overflowAt: Date?
            for d in dayDrinks {
                running += d.ml
                if goalAt == nil, running >= goal { goalAt = d.at }
                if overflowAt == nil, running * 100 >= goal * Rules.volumeCapPercent { overflowAt = d.at }
                s.totalDrinks += 1
                s.totalML += d.ml
                unlock(.firstSip, d.at)
                if d.onCue {
                    s.onCueCount += 1
                    s.xp += Rules.onCueXP
                }
                if Rules.earlyBirdHours.contains(cal.component(.hour, from: d.at)) { unlock(.earlyBird, d.at) }
                if s.onCueCount >= 10 { unlock(.quickDraw, d.at) }
                if s.onCueCount >= 100 { unlock(.reflexes, d.at) }
                if s.totalML >= 10_000 { unlock(.tenLiters, d.at) }
                if s.totalDrinks >= 100 { unlock(.centurion, d.at) }
            }

            if total >= goal, let goalAt {
                s.streak += 1
                s.xp += Rules.goalXP + Rules.streakXPPerDay * min(s.streak, Rules.streakXPMaxDays)
                if s.streak % Rules.freezeEvery == 0 { s.freezes = min(Rules.maxFreezes, s.freezes + 1) }
                unlock(.goalGetter, goalAt)
                if let overflowAt { unlock(.overflow, overflowAt) }
                if lostStreak >= 3 { unlock(.comeback, goalAt) }
                lostStreak = 0
                for (len, a) in [(3, Achievement.hatTrick), (7, .weekWarrior), (14, .fortnight), (30, .monsoon)]
                where s.streak >= len { unlock(a, goalAt) }
            } else if !isToday {
                // A finished day that missed the goal. Off days are neutral; a freeze covers one miss.
                let offDay = !prefs.activeWeekdays.contains(cal.component(.weekday, from: day))
                if offDay || s.streak == 0 {
                    // nothing to lose
                } else if s.freezes > 0 {
                    s.freezes -= 1
                } else {
                    lostStreak = s.streak
                    s.streak = 0
                }
            }
            s.bestStreak = max(s.bestStreak, s.streak)

            if isToday {
                s.todayML = total
                s.todayGoal = goal
                let activeDay = prefs.activeWeekdays.contains(cal.component(.weekday, from: day))
                s.streakAtRisk = s.streak > 0 && total < goal && activeDay
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = cal.startOfDay(for: next)
        }

        if s.todayGoal == 0 { s.todayGoal = min(Rules.maxGoalML, max(1, prefs.dailyGoalML)) }   // clock set before startedAt
        s.week = (0..<7).reversed().compactMap { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
            let key = cal.dayKey(d)
            let ml = (byDay[key] ?? []).reduce(0) { $0 + $1.ml }
            return DayTotal(day: d, ml: ml, goal: goalByDay[key] ?? max(1, prefs.dailyGoalML))
        }
        return s
    }
}
