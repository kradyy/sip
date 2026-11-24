import Testing
import Foundation
@testable import SipCore

// "Today" in the hand-written scenarios is Wednesday 2026-06-10 15:00 (Europe/Stockholm).
// Weekday numbers: 1 = Sun, 2 = Mon, 3 = Tue, 4 = Wed, 5 = Thu, 6 = Fri, 7 = Sat.

/// One character per day, oldest first, last character = today.
/// G = exactly the goal in one drink at 12:00, X = 150% of goal, h = half the goal, . = nothing.
struct Sim {
    var e = Env()
    var prefs = P(goal: 2000)
    var today = "2026-06-10"
    var goals: [String: Int] = [:]
    var now: Date { e.d("\(today) 15:00") }

    func ledger(_ pattern: String) -> Ledger {
        let chars = Array(pattern), n = chars.count
        var drinks: [Drink] = []
        for (i, c) in chars.enumerated() {
            let day = civil(today, plus: i - (n - 1))
            let ml: Int
            switch c {
            case "G": ml = prefs.dailyGoalML
            case "X": ml = prefs.dailyGoalML * 3 / 2
            case "h": ml = prefs.dailyGoalML / 2
            default: continue
            }
            drinks.append(Drink(at: e.d("\(day) 12:00"), ml: ml))
        }
        return Ledger(startedAt: e.d("\(civil(today, plus: -(n - 1))) 09:00"), drinks: drinks, goals: goals)
    }

    func run(_ pattern: String) -> Stats {
        Progression.compute(ledger: ledger(pattern), prefs: prefs, now: now, calendar: e.cal)
    }
}

func unlockedSet(_ s: Stats) -> Set<Achievement> { Set(s.unlocked.keys) }

@Suite("Progression · basics")
struct ProgressionBasicsTests {
    let e = Env()

    @Test func emptyLedger() {
        let now = e.d("2026-06-10 15:00")
        let s = Progression.compute(ledger: Ledger(startedAt: now), prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(s.xp == 0)
        #expect(s.streak == 0)
        #expect(s.bestStreak == 0)
        #expect(s.freezes == 0)
        #expect(s.todayML == 0)
        #expect(s.todayGoal == 2000)
        #expect(s.streakAtRisk == false)
        #expect(s.unlocked.isEmpty)
        #expect(s.level == 1)
        #expect(s.week.count == 7)
        #expect(s.week.allSatisfy { $0.ml == 0 })
    }

    @Test func emptyLedgerStartedLongAgo() {
        let now = e.d("2026-06-10 15:00")
        let s = Progression.compute(ledger: Ledger(startedAt: e.d("2026-01-01")), prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(s.xp == 0 && s.streak == 0 && s.bestStreak == 0 && s.week.count == 7)
    }

    @Test func clockBeforeStartedAtDoesNotCrashAndStillReportsToday() {
        let now = e.d("2026-06-10 15:00")
        let s = Progression.compute(ledger: Ledger(startedAt: e.d("2026-06-12 09:00")), prefs: P(goal: 1800), now: now, calendar: e.cal)
        #expect(s.todayGoal == 1800)
        #expect(s.todayML == 0)
        #expect(s.week.count == 7)
        #expect(e.cal.dayKey(s.week.last!.day) == "2026-06-10")
    }

    @Test func singleDrinkXP() {
        // 250 ml = 10 volume XP, + 25 for First Sip.
        let now = e.d("2026-06-10 15:00")
        let l = Ledger(startedAt: e.d("2026-06-10 09:00"), drinks: [Drink(at: e.d("2026-06-10 12:00"), ml: 250)])
        let s = Progression.compute(ledger: l, prefs: P(goal: 2500), now: now, calendar: e.cal)
        #expect(s.xp == 35)
        #expect(s.todayML == 250)
        #expect(s.totalML == 250)
        #expect(s.totalDrinks == 1)
        #expect(unlockedSet(s) == [.firstSip])
        #expect(s.streak == 0)
        #expect(s.streakAtRisk == false)   // streak is 0, nothing to protect
    }

    @Test func onCueDrinksGiveFiveXPEach() {
        let now = e.d("2026-06-10 15:00")
        let l = Ledger(startedAt: e.d("2026-06-10 09:00"), drinks: [
            Drink(at: e.d("2026-06-10 12:00"), ml: 250, onCue: true),
            Drink(at: e.d("2026-06-10 13:00"), ml: 250, onCue: false),
            Drink(at: e.d("2026-06-10 14:00"), ml: 250, onCue: true),
        ])
        let s = Progression.compute(ledger: l, prefs: P(goal: 2500), now: now, calendar: e.cal)
        #expect(s.onCueCount == 2)
        #expect(s.xp == 30 + 10 + 25)       // 750 ml / 25, two cues, First Sip
    }

    @Test func volumeXPIsFlooredPer25ml() {
        let now = e.d("2026-06-10 15:00")
        func xp(_ ml: Int) -> Int {
            let l = Ledger(startedAt: e.d("2026-06-10 09:00"), drinks: [Drink(at: e.d("2026-06-10 12:00"), ml: ml)])
            return Progression.compute(ledger: l, prefs: P(goal: 100_000), now: now, calendar: e.cal).xp - 25
        }
        #expect(xp(24) == 0)
        #expect(xp(25) == 1)
        #expect(xp(49) == 1)
        #expect(xp(50) == 2)
    }

    @Test func volumeXPIsCappedAt150PercentOfGoalWithIntegerMath() {
        let now = e.d("2026-06-10 15:00")
        // goal 2500, 5000 ml: cap 3750 → 150 volume XP; goal day streak 1 → 55; First Sip 25 + Goal Getter 50 + Overflow 75.
        let big = Ledger(startedAt: e.d("2026-06-10 09:00"), drinks: [Drink(at: e.d("2026-06-10 12:00"), ml: 5000)])
        #expect(Progression.compute(ledger: big, prefs: P(goal: 2500), now: now, calendar: e.cal).xp == 150 + 55 + 25 + 50 + 75)
        // goal 1001: cap is 1001*150/100 = 1501 (floor of 1501.5) → 60 volume XP.
        let odd = Ledger(startedAt: e.d("2026-06-10 09:00"), drinks: [Drink(at: e.d("2026-06-10 12:00"), ml: 1600)])
        #expect(Progression.compute(ledger: odd, prefs: P(goal: 1001), now: now, calendar: e.cal).xp == 60 + 55 + 25 + 50 + 75)
        // 1501 ml is below 150.0% of 1001 (1501.5): no Overflow.
        let edge = Ledger(startedAt: e.d("2026-06-10 09:00"), drinks: [Drink(at: e.d("2026-06-10 12:00"), ml: 1501)])
        let s = Progression.compute(ledger: edge, prefs: P(goal: 1001), now: now, calendar: e.cal)
        #expect(s.xp == 60 + 55 + 25 + 50)
        #expect(!s.unlocked.keys.contains(.overflow))
    }

    @Test func threeDayStreakXPAnchor() {
        // 3 × (80 volume + 50 goal) + streak bonus 5+10+15 + First Sip 25 + Goal Getter 50 + Hat Trick 75.
        let s = Sim().run("GGG")
        #expect(s.xp == 3 * 130 + 30 + 25 + 50 + 75)
        #expect(s.streak == 3)
        #expect(s.totalML == 6000)
    }

    @Test func streakBonusStopsGrowingAtTwentyDays() {
        let s = Sim().run(String(repeating: "G", count: 25))
        var want = 0
        for day in 1...25 { want += 80 + 50 + 5 * min(day, 20) }
        want += 25 + 50 + 75 + 100 + 150 + 250      // First Sip, Goal Getter, Hat Trick, Ten Liters, Week Warrior, Fortnight
        #expect(s.xp == want)
        #expect(s.streak == 25)
        #expect(s.bestStreak == 25)
    }

    @Test func drinksAfterNowAreIgnoredCompletely() {
        let now = e.d("2026-06-10 15:00")
        let l = Ledger(startedAt: e.d("2026-06-10 09:00"), drinks: [
            Drink(at: now.addingTimeInterval(1), ml: 5000, onCue: true),
            Drink(at: e.d("2026-06-11 08:00"), ml: 5000),
        ])
        let s = Progression.compute(ledger: l, prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(s.xp == 0)
        #expect(s.totalDrinks == 0)
        #expect(s.totalML == 0)
        #expect(s.todayML == 0)
        #expect(s.onCueCount == 0)
        #expect(s.unlocked.isEmpty)
        #expect(s.week.allSatisfy { $0.ml == 0 })
    }

    @Test func drinkExactlyAtNowCounts() {
        let now = e.d("2026-06-10 15:00")
        let l = Ledger(startedAt: e.d("2026-06-10 09:00"), drinks: [Drink(at: now, ml: 300)])
        let s = Progression.compute(ledger: l, prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(s.todayML == 300)
        #expect(s.totalDrinks == 1)
    }

    @Test(arguments: [0, -1, -250])
    func nonPositiveDrinksAreIgnoredCompletely(_ ml: Int) {
        let now = e.d("2026-06-10 15:00")
        let l = Ledger(startedAt: e.d("2026-06-10 09:00"), drinks: [
            Drink(at: e.d("2026-06-10 05:00"), ml: ml, onCue: true),    // would also be an Early Bird drink
        ])
        let s = Progression.compute(ledger: l, prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(s.xp == 0)
        #expect(s.totalDrinks == 0)
        #expect(s.totalML == 0)
        #expect(s.onCueCount == 0)
        #expect(s.todayML == 0)
        #expect(s.unlocked.isEmpty)
    }

    @Test func nonPositiveDrinkDoesNotCancelAValidOne() {
        let now = e.d("2026-06-10 15:00")
        let l = Ledger(startedAt: e.d("2026-06-10 09:00"), drinks: [
            Drink(at: e.d("2026-06-10 10:00"), ml: 500),
            Drink(at: e.d("2026-06-10 11:00"), ml: -300),
        ])
        let s = Progression.compute(ledger: l, prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(s.todayML == 500)
        #expect(s.totalML == 500)
    }

    @Test func drinksBeforeStartedAtStillCountAndExtendTheReplay() {
        let now = e.d("2026-06-10 15:00")
        let l = Ledger(startedAt: e.d("2026-06-09 08:00"), drinks: [
            Drink(at: e.d("2026-06-07 12:00"), ml: 2000),
            Drink(at: e.d("2026-06-10 12:00"), ml: 100),
        ])
        let s = Progression.compute(ledger: l, prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(s.totalML == 2100)
        #expect(s.totalDrinks == 2)
        #expect(s.bestStreak == 1)                       // 06-07 was a goal day in the replay
        #expect(unlockedSet(s).isSuperset(of: [.firstSip, .goalGetter]))
        #expect(s.week[3].ml == 2000)                    // 06-07
        #expect(e.cal.dayKey(s.week[3].day) == "2026-06-07")
    }

    @Test func daysBeforeTheLedgerStartShowZero() {
        let now = e.d("2026-06-10 15:00")
        let l = Ledger(startedAt: e.d("2026-06-09 08:00"), drinks: [Drink(at: e.d("2026-06-10 12:00"), ml: 400)])
        let s = Progression.compute(ledger: l, prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(s.week.map(\.ml) == [0, 0, 0, 0, 0, 0, 400])
    }

    @Test func weekIsSevenDaysOldestFirstEndingToday() {
        let now = e.d("2026-06-10 15:00")
        var drinks: [Drink] = []
        for back in 0..<10 { drinks.append(Drink(at: e.d("\(civil("2026-06-10", plus: -back)) 12:00"), ml: 100 + back)) }
        let l = Ledger(startedAt: e.d("2026-05-25"), drinks: drinks)
        let s = Progression.compute(ledger: l, prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(s.week.map { e.cal.dayKey($0.day) } == (0..<7).map { civil("2026-06-10", plus: $0 - 6) })
        #expect(s.week.map(\.ml) == [106, 105, 104, 103, 102, 101, 100])
        #expect(s.week.allSatisfy { e.cal.startOfDay(for: $0.day) == $0.day })
        #expect(s.week.last?.met == false)
    }

    @Test func midnightDrinkBelongsToTheNewDay() {
        let now = e.d("2026-06-10 15:00")
        let l = Ledger(startedAt: e.d("2026-06-08 08:00"), drinks: [
            Drink(at: e.d("2026-06-08 23:59:59"), ml: 200),
            Drink(at: e.d("2026-06-09 00:00:00"), ml: 300),
            Drink(at: e.d("2026-06-09 23:59:59"), ml: 40),
            Drink(at: e.d("2026-06-10 00:00:00"), ml: 5),
        ])
        let s = Progression.compute(ledger: l, prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(Array(s.week.suffix(3)).map(\.ml) == [200, 340, 5])
        #expect(s.todayML == 5)
        #expect(!s.unlocked.keys.contains(.earlyBird))     // 00:00 is a night owl, not an early bird
    }

    @Test func nowExactlyAtMidnightStartsAFreshDay() {
        let now = e.d("2026-06-10 00:00:00")
        let l = Ledger(startedAt: e.d("2026-06-09 08:00"), drinks: [
            Drink(at: now.addingTimeInterval(-1), ml: 700),
            Drink(at: now, ml: 100),
        ])
        let s = Progression.compute(ledger: l, prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(s.todayML == 100)
        #expect(s.week[5].ml == 700)
    }

    @Test func historyLongerThanTenYearsStaysFast() {
        let now = e.d("2026-06-10 15:00")
        let l = Ledger(startedAt: .distantPast, drinks: [Drink(at: e.d("2026-06-10 12:00"), ml: 300)])
        let clock = ContinuousClock()
        var s = Stats()
        let t = clock.measure { s = Progression.compute(ledger: l, prefs: P(goal: 2000), now: now, calendar: e.cal) }
        #expect(t < .seconds(2), "took \(t)")
        #expect(s.todayML == 300)
    }

    @Test func threeYearsOfEightDrinksADayComputesQuickly() {
        let now = e.d("2026-11-23 15:00")
        var drinks: [Drink] = []
        let first = civil("2026-11-23", plus: -1095)
        for off in 0..<1095 {
            let base = e.d(civil(first, plus: off))
            for k in 0..<8 { drinks.append(Drink(at: base.addingTimeInterval(TimeInterval(8 * 3600 + k * 5400)), ml: 300, onCue: k % 2 == 0)) }
        }
        let l = Ledger(startedAt: e.d(first), drinks: drinks)
        let clock = ContinuousClock()
        var runs: [Duration] = []
        var s = Stats()
        for _ in 0..<3 { runs.append(clock.measure { s = Progression.compute(ledger: l, prefs: P(goal: 2000), now: now, calendar: e.cal) }) }
        print("PERF 3y×8 drinks/day compute: \(runs)")
        #expect(runs.min()! < .seconds(1), "best of 3 was \(runs.min()!); all: \(runs)")
        #expect(runs[0] < .seconds(1), "first (cold) run took \(runs[0])")
        #expect(s.totalDrinks == drinks.count)
        #expect(s.bestStreak >= 1000)           // 2400 ml/day against a 2000 ml goal, every day
    }
}

struct StreakCase: Sendable, CustomTestStringConvertible {
    var pattern: String
    var streak: Int
    var best: Int
    var freezes: Int
    var atRisk: Bool
    var days: Set<Int> = Set(1...7)
    var testDescription: String { "\(pattern) days=\(days.sorted())" }
}

@Suite("Progression · streaks and freezes")
struct StreakTests {
    static let cases: [StreakCase] = [
        .init(pattern: ".", streak: 0, best: 0, freezes: 0, atRisk: false),
        .init(pattern: "G", streak: 1, best: 1, freezes: 0, atRisk: false),
        .init(pattern: "h", streak: 0, best: 0, freezes: 0, atRisk: false),
        .init(pattern: "GG.", streak: 2, best: 2, freezes: 0, atRisk: true),             // today never breaks it
        .init(pattern: "GGG.G", streak: 1, best: 3, freezes: 0, atRisk: false),          // lost, restarted
        .init(pattern: "GGG..", streak: 0, best: 3, freezes: 0, atRisk: false),
        .init(pattern: "GGGGGGG.", streak: 7, best: 7, freezes: 1, atRisk: true),         // freeze earned at 7
        .init(pattern: "GGGGGGG..", streak: 7, best: 7, freezes: 0, atRisk: true),        // miss eats the freeze, streak unchanged
        .init(pattern: "GGGGGGG...", streak: 0, best: 7, freezes: 0, atRisk: false),      // second miss breaks it
        .init(pattern: "GGGGGGG.G", streak: 8, best: 8, freezes: 0, atRisk: false),       // frozen day not counted, next goal day +1
        .init(pattern: "GGGGGGG..G", streak: 1, best: 7, freezes: 0, atRisk: false),
        .init(pattern: "GGGGGGG.GGGGGGG", streak: 14, best: 14, freezes: 1, atRisk: false),   // 14 re-earns a freeze
        .init(pattern: String(repeating: "G", count: 14) + ".", streak: 14, best: 14, freezes: 2, atRisk: true),
        .init(pattern: String(repeating: "G", count: 21) + ".", streak: 21, best: 21, freezes: 2, atRisk: true),    // capped at 2
        .init(pattern: String(repeating: "G", count: 28) + ".", streak: 28, best: 28, freezes: 2, atRisk: true),
        .init(pattern: String(repeating: "G", count: 28) + "..G", streak: 29, best: 29, freezes: 0, atRisk: false), // two misses, two freezes
        .init(pattern: String(repeating: "G", count: 28) + "...G", streak: 1, best: 28, freezes: 0, atRisk: false), // third miss breaks
        .init(pattern: String(repeating: "G", count: 21) + "...G", streak: 1, best: 21, freezes: 0, atRisk: false),
        // Off days (Sat/Sun disabled): neutral, even when the streak is long and no freeze is left.
        .init(pattern: "GGG..GGG", streak: 6, best: 6, freezes: 0, atRisk: false, days: [2, 3, 4, 5, 6]),
        .init(pattern: "GGG..GGG", streak: 3, best: 3, freezes: 0, atRisk: false),            // same days, all enabled → Saturday breaks it, restart from Monday
        .init(pattern: "GGGGGGGG", streak: 8, best: 8, freezes: 1, atRisk: false, days: [2, 3, 4, 5, 6]),   // goal met on off days counts
        .init(pattern: "G..", streak: 0, best: 1, freezes: 0, atRisk: false, days: [2, 3, 4, 5, 6]),         // Tue miss at 06-09 is an active day
        // Off days don't eat freezes; the Monday miss does.
        .init(pattern: "GGGGGGG...GG", streak: 9, best: 9, freezes: 0, atRisk: false, days: [2, 3, 4, 5, 6]),
        // Today is an off day: not at risk.
        .init(pattern: "GGG.", streak: 3, best: 3, freezes: 0, atRisk: false, days: [1, 2, 3, 5, 6, 7]),
        .init(pattern: "GGG.", streak: 3, best: 3, freezes: 0, atRisk: true, days: [1, 2, 3, 4, 5, 6, 7]),
        // Half-goal days are plain misses.
        .init(pattern: "GGhG", streak: 1, best: 2, freezes: 0, atRisk: false),
        // Streak met only on today.
        .init(pattern: "..G", streak: 1, best: 1, freezes: 0, atRisk: false),
    ]

    @Test(arguments: cases)
    func streakScenarios(_ c: StreakCase) {
        var sim = Sim()
        sim.prefs.activeWeekdays = c.days
        let s = sim.run(c.pattern)
        #expect(s.streak == c.streak, "streak")
        #expect(s.bestStreak == c.best, "bestStreak")
        #expect(s.freezes == c.freezes, "freezes")
        #expect(s.streakAtRisk == c.atRisk, "streakAtRisk")
    }

    @Test func streakIncludesTodayOnlyOnceGoalIsMet() {
        #expect(Sim().run("GGG.").streak == 3)
        #expect(Sim().run("GGGG").streak == 4)
        #expect(Sim().run("GGGh").streak == 3)
    }

    @Test func weekdayFlipsForOffDayMissWithoutBurningAFreezeAtSevenStreak() {
        // Fri 06-05 … goal met 7 days ending Fri, Sat+Sun off and missed, Mon missed (freeze eaten), Tue/Wed met.
        var sim = Sim()
        sim.prefs.activeWeekdays = [2, 3, 4, 5, 6]
        let s = sim.run("GGGGGGG...GG")
        #expect(s.freezes == 0)
        #expect(s.streak == 9)
    }
}

@Suite("Progression · goals")
struct GoalTests {
    @Test func carryForwardAndInitialCarryFromSmallestKey() {
        var sim = Sim()
        sim.goals = ["2026-06-05": 1000, "2026-06-08": 3000]
        let s = sim.run(".......")        // 06-04 … 06-10
        #expect(s.week.map(\.goal) == [1000, 1000, 1000, 1000, 3000, 3000, 2000])
        #expect(s.todayGoal == 2000)
    }

    @Test func goalInEffectDecidesWhetherADayWasMet() {
        var sim = Sim()
        sim.goals = ["2026-06-04": 1000, "2026-06-08": 3000]
        var l = sim.ledger(".......")       // 06-04 … 06-10, drinks added by hand
        for day in ["2026-06-04", "2026-06-05", "2026-06-06", "2026-06-07"] { l.drinks.append(Drink(at: sim.e.d("\(day) 12:00"), ml: 1000)) }
        l.drinks.append(Drink(at: sim.e.d("2026-06-08 12:00"), ml: 2999))     // misses the new 3000
        l.drinks.append(Drink(at: sim.e.d("2026-06-09 12:00"), ml: 3000))
        l.drinks.append(Drink(at: sim.e.d("2026-06-10 12:00"), ml: 2000))     // today uses prefs: 2000
        let s = Progression.compute(ledger: l, prefs: sim.prefs, now: sim.now, calendar: sim.e.cal)
        #expect(s.bestStreak == 4)
        #expect(s.streak == 2)
        #expect(s.unlocked.keys.contains(.comeback))
        #expect(s.week.map(\.goal) == [1000, 1000, 1000, 1000, 3000, 3000, 2000])
    }

    @Test func todaysGoalIsAlwaysThePrefsGoalNeverTheLedgerEntry() {
        var sim = Sim()
        sim.goals = ["2026-06-10": 5000]
        let s = sim.run("G")
        #expect(s.todayGoal == 2000)
        #expect(s.goalMet)
        #expect(s.streak == 1)
    }

    @Test func goalEntriesInTheFutureAreIgnored() {
        var sim = Sim()
        sim.goals = ["2026-06-20": 99_999]
        let s = sim.run("GG")
        #expect(s.todayGoal == 2000)
        // The smallest key seeds the carry (spec rule 6), so past days inherit it: 99999.
        #expect(s.week[5].goal == 99_999)
    }

    @Test func goalIsAtLeastOne() {
        var sim = Sim()
        sim.goals = ["2026-06-07": 0, "2026-06-08": -100]
        let l = Ledger(startedAt: sim.e.d("2026-06-06 09:00"),
                       drinks: [Drink(at: sim.e.d("2026-06-07 12:00"), ml: 1)], goals: sim.goals)
        let s = Progression.compute(ledger: l, prefs: sim.prefs, now: sim.now, calendar: sim.e.cal)
        #expect(s.week.allSatisfy { $0.goal >= 1 })
        // 06-06 .. 06-08 all use goal 1: 06-07 (week[3]) has 1 ml → met; the empty days around it are not.
        #expect(s.week[3].ml == 1)
        #expect(s.week[3].met)
        #expect(s.week[2].met == false)
        #expect(s.week[4].met == false)
    }

    @Test(arguments: [0, -500])
    func zeroOrNegativePrefsGoalStillMeansAtLeastOne(_ goal: Int) {
        var sim = Sim()
        sim.prefs.dailyGoalML = goal
        let empty = Progression.compute(ledger: Ledger(startedAt: sim.now), prefs: sim.prefs, now: sim.now, calendar: sim.e.cal)
        #expect(empty.todayGoal == 1)
        #expect(empty.goalMet == false)
        #expect(empty.streak == 0)
        let l = Ledger(startedAt: sim.now, drinks: [Drink(at: sim.e.d("2026-06-10 12:00"), ml: 1)])
        let one = Progression.compute(ledger: l, prefs: sim.prefs, now: sim.now, calendar: sim.e.cal)
        #expect(one.todayGoal == 1)
        #expect(one.goalMet)
        #expect(one.streak == 1)
    }

    @Test func noGoalsMapSeedsPastDaysFromPrefs() {
        var sim = Sim()
        sim.prefs.dailyGoalML = 1234
        let s = sim.run("......")
        #expect(s.week.map(\.goal).allSatisfy { $0 == 1234 })
    }
}

@Suite("Progression · achievements")
struct AchievementTests {
    let e = Env()

    @Test(arguments: [1, 2, 3, 6, 7, 13, 14, 29, 30, 31])
    func streakAchievementsUnlockAtExactLengths(_ n: Int) {
        let s = Sim().run(String(repeating: "G", count: n))
        var want: Set<Achievement> = [.firstSip, .goalGetter]
        if n >= 3 { want.insert(.hatTrick) }
        if n >= 5 { want.insert(.tenLiters) }          // 5 × 2000 ml
        if n >= 7 { want.insert(.weekWarrior) }
        if n >= 14 { want.insert(.fortnight) }
        if n >= 30 { want.insert(.monsoon) }
        #expect(unlockedSet(s) == want)
    }

    @Test func streakAchievementsStayAfterTheStreakBreaks() {
        let s = Sim().run("GGGGGGGG....")     // 8 days, then 3 misses (freeze, then break), today miss
        #expect(s.streak == 0)
        #expect(unlockedSet(s).isSuperset(of: [.hatTrick, .weekWarrior]))
        #expect(!unlockedSet(s).contains(.fortnight))
    }

    @Test(arguments: [(2500, 3750, true), (2500, 3749, false), (1001, 1501, false), (1001, 1502, true), (1, 2, true), (1, 1, false)])
    func overflowIsAtLeast150PercentOfGoal(_ goal: Int, _ ml: Int, _ unlocked: Bool) {
        let now = e.d("2026-06-10 15:00")
        let l = Ledger(startedAt: e.d("2026-06-10 09:00"), drinks: [Drink(at: e.d("2026-06-10 12:00"), ml: ml)])
        let s = Progression.compute(ledger: l, prefs: P(goal: goal), now: now, calendar: e.cal)
        #expect(s.unlocked.keys.contains(.overflow) == unlocked, "goal \(goal), \(ml) ml")
    }

    @Test(arguments: [
        ("Europe/Stockholm", "2026-06-10 07:59:59", true),
        ("Europe/Stockholm", "2026-06-10 08:00:00", false),
        ("Europe/Stockholm", "2026-06-10 00:00:00", false),
        ("Europe/Stockholm", "2026-06-10 04:59:59", false),
        ("Europe/Stockholm", "2026-06-10 05:00:00", true),
        ("Europe/Stockholm", "2026-06-10 09:30:00", false),     // 07:30 UTC: must not read the UTC hour
        ("Europe/Stockholm", "2026-06-10 07:30:00", true),      // 05:30 UTC
        ("America/New_York", "2026-06-10 06:30:00", true),
        ("America/New_York", "2026-06-10 08:30:00", false),
        ("America/New_York", "2026-06-10 03:30:00", false),
        ("Pacific/Auckland", "2026-06-10 20:00:00", false),     // 08:00 UTC
        ("Asia/Kolkata", "2026-06-10 07:00:00", true),
    ])
    func earlyBirdUsesLocalHour(_ tz: String, _ at: String, _ unlocked: Bool) {
        let e = Env(tz)
        let now = e.d("2026-06-10 23:00")
        let l = Ledger(startedAt: e.d("2026-06-10 00:00"), drinks: [Drink(at: e.d(at), ml: 100)])
        let s = Progression.compute(ledger: l, prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(s.unlocked.keys.contains(.earlyBird) == unlocked, "\(tz) \(at)")
    }

    @Test(arguments: [(9, false), (10, true)])
    func quickDrawAtTenOnCueDrinks(_ n: Int, _ unlocked: Bool) {
        let now = e.d("2026-06-10 15:00")
        var drinks = (0..<n).map { Drink(at: e.d("2026-06-10 10:\(String(format: "%02ld", $0))"), ml: 1, onCue: true) }
        drinks += (0..<30).map { Drink(at: e.d("2026-06-10 11:\(String(format: "%02ld", $0))"), ml: 1, onCue: false) }
        let s = Progression.compute(ledger: Ledger(startedAt: e.d("2026-06-10 09:00"), drinks: drinks), prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(s.unlocked.keys.contains(.quickDraw) == unlocked)
        #expect(s.onCueCount == n)
    }

    @Test func quickDrawCountsAcrossDays() {
        let now = e.d("2026-06-10 15:00")
        var drinks: [Drink] = []
        for back in 0..<5 {
            let day = civil("2026-06-10", plus: -back)
            drinks.append(Drink(at: e.d("\(day) 12:00"), ml: 1, onCue: true))
            drinks.append(Drink(at: e.d("\(day) 13:00"), ml: 1, onCue: true))
        }
        let s = Progression.compute(ledger: Ledger(startedAt: e.d("2026-06-05"), drinks: drinks), prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(s.unlocked.keys.contains(.quickDraw))
        #expect(!s.unlocked.keys.contains(.reflexes))
    }

    @Test(arguments: [(99, false), (100, true)])
    func reflexesAtHundredOnCueDrinks(_ n: Int, _ unlocked: Bool) {
        let now = e.d("2026-06-10 15:00")
        var drinks: [Drink] = []
        for i in 0..<n { drinks.append(Drink(at: e.d("\(civil("2026-06-10", plus: -(i / 20))) 10:\(String(format: "%02ld", i % 20))"), ml: 1, onCue: true)) }
        let s = Progression.compute(ledger: Ledger(startedAt: e.d("2026-06-01"), drinks: drinks), prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(s.unlocked.keys.contains(.reflexes) == unlocked)
        #expect(s.unlocked.keys.contains(.quickDraw))
    }

    @Test(arguments: [(9_999, false), (10_000, true), (10_001, true)])
    func tenLitersIsLifetimeTotal(_ total: Int, _ unlocked: Bool) {
        let now = e.d("2026-06-10 15:00")
        // Spread over four days, none of them a goal day.
        let parts = [total / 4, total / 4, total / 4, total - 3 * (total / 4)]
        let drinks = parts.enumerated().map { Drink(at: e.d("\(civil("2026-06-10", plus: -$0.offset)) 12:00"), ml: $0.element) }
        let s = Progression.compute(ledger: Ledger(startedAt: e.d("2026-06-07"), drinks: drinks), prefs: P(goal: 20_000), now: now, calendar: e.cal)
        #expect(s.totalML == total)
        #expect(s.unlocked.keys.contains(.tenLiters) == unlocked)
    }

    @Test(arguments: [(99, false), (100, true)])
    func centurionAtHundredDrinks(_ n: Int, _ unlocked: Bool) {
        let now = e.d("2026-06-10 15:00")
        let drinks = (0..<n).map { Drink(at: e.d("2026-06-\(String(format: "%02ld", 1 + $0 / 20)) 10:\(String(format: "%02ld", $0 % 20))"), ml: 1) }
        let s = Progression.compute(ledger: Ledger(startedAt: e.d("2026-06-01"), drinks: drinks), prefs: P(goal: 20_000), now: now, calendar: e.cal)
        #expect(s.unlocked.keys.contains(.centurion) == unlocked)
        #expect(s.totalDrinks == n)
    }

    @Test func ignoredDrinksDoNotCountTowardCenturion() {
        let now = e.d("2026-06-10 15:00")
        var drinks = (0..<99).map { Drink(at: e.d("2026-06-09 10:\(String(format: "%02ld", $0 % 60))"), ml: 1) }
        drinks += (0..<10).map { Drink(at: e.d("2026-06-09 12:\(String(format: "%02ld", $0))"), ml: 0) }
        drinks += (0..<10).map { Drink(at: e.d("2026-06-11 12:\(String(format: "%02ld", $0))"), ml: 5) }
        let s = Progression.compute(ledger: Ledger(startedAt: e.d("2026-06-01"), drinks: drinks), prefs: P(goal: 20_000), now: now, calendar: e.cal)
        #expect(s.totalDrinks == 99)
        #expect(!s.unlocked.keys.contains(.centurion))
    }

    // Comeback Kid: first goal day after a streak of 3+ was LOST.
    @Test(arguments: [
        ("GGG.G", true),          // lost 3, back on the very next day
        ("GGG..G", true),         // still the first goal day after the loss
        ("GGGG...G", true),
        ("GG.G", false),          // only 2 lost
        ("GGG..", false),         // not back yet
        ("GGGG.", false),
        ("GGGGGGG.G", false),     // freeze saved the miss: nothing was lost
        ("GGGGGGG..G", true),     // lost 7 after the freeze ran out
        ("G.GGG.G", true),        // second streak of 3 lost then recovered
        ("GGG.GGG.G", true),
    ])
    func comebackKid(_ pattern: String, _ unlocked: Bool) {
        let s = Sim().run(pattern)
        #expect(s.unlocked.keys.contains(.comeback) == unlocked, "\(pattern)")
    }

    @Test func comebackOnlyAfterLossNotAfterOffDayMisses() {
        var sim = Sim()
        sim.prefs.activeWeekdays = [2, 3, 4, 5, 6]
        let s = sim.run("GGG..GGG")      // Sat/Sun misses are neutral
        #expect(!s.unlocked.keys.contains(.comeback))
    }

    @Test func eachAchievementPaysItsXPOnlyOnce() {
        // A streak of 3 earned twice (lost in between) must not pay Hat Trick twice.
        var sim = Sim()
        sim.prefs.dailyGoalML = 1000          // keeps lifetime volume below 10 L so Ten Liters stays out of the picture
        let once = sim.run("GGG.G")
        let twice = sim.run("GGG.GGG")
        // The second run adds 2 more goal days: volume 40 + 50 + streak bonus (2 → 10, 3 → 15) each; Hat Trick is not paid again.
        #expect(twice.xp - once.xp == (40 + 50 + 10) + (40 + 50 + 15))
        #expect(twice.unlocked.count == once.unlocked.count)
    }

    @Test func achievementXPTable() {
        let want: [Achievement: Int] = [
            .firstSip: 25, .goalGetter: 50, .quickDraw: 50, .hatTrick: 75, .overflow: 75, .earlyBird: 75, .comeback: 75,
            .tenLiters: 100, .weekWarrior: 150, .centurion: 150, .fortnight: 250, .reflexes: 250, .monsoon: 500,
        ]
        #expect(Set(want.keys) == Set(Achievement.allCases))
        for (a, xp) in want { #expect(a.xp == xp, "\(a)") }
    }
}

@Suite("Progression · DST")
struct ProgressionDSTTests {
    @Test(arguments: Zone.every)
    func streakIsNotSkippedOrDoubledAcrossSpringForward(_ z: Zone) {
        var sim = Sim()
        sim.e = Env(z.id)
        sim.today = civil(z.spring, plus: 5)
        let s = sim.run(String(repeating: "G", count: 12))
        #expect(s.streak == 12)
        #expect(s.week.map { sim.e.cal.dayKey($0.day) } == (0..<7).map { civil(sim.today, plus: $0 - 6) })
        #expect(s.week.allSatisfy { $0.ml == 2000 })
    }

    @Test(arguments: Zone.every)
    func streakIsNotSkippedOrDoubledAcrossFallBack(_ z: Zone) {
        var sim = Sim()
        sim.e = Env(z.id)
        sim.today = civil(z.fall, plus: 5)
        let s = sim.run(String(repeating: "G", count: 12))
        #expect(s.streak == 12)
        #expect(s.week.map { sim.e.cal.dayKey($0.day) } == (0..<7).map { civil(sim.today, plus: $0 - 6) })
        #expect(s.week.allSatisfy { $0.ml == 2000 })
    }

    @Test(arguments: Zone.every)
    func todayIsTheDSTDay(_ z: Zone) {
        for day in [z.spring, z.fall] {
            var sim = Sim()
            sim.e = Env(z.id)
            sim.today = day
            let s = sim.run("GGGG")
            #expect(s.streak == 4, "today = \(day)")
            #expect(s.todayML == 2000)
            #expect(s.week.map { sim.e.cal.dayKey($0.day) } == (0..<7).map { civil(day, plus: $0 - 6) })
        }
    }

    @Test(arguments: Zone.all)
    func lateNightAndMidnightDrinksOnDSTDaysLandOnTheRightDay(_ z: Zone) {
        let e = Env(z.id)
        for day in [z.spring, z.fall] {
            let prev = civil(day, plus: -1), next = civil(day, plus: 1)
            let now = e.d("\(next) 12:00")
            let l = Ledger(startedAt: e.d("\(prev) 08:00"), drinks: [
                Drink(at: e.d("\(prev) 23:59:59"), ml: 10),
                Drink(at: e.d("\(day) 00:00:00"), ml: 20),
                Drink(at: e.d("\(day) 05:00:00"), ml: 30),
                Drink(at: e.d("\(day) 23:59:59"), ml: 40),
                Drink(at: e.d("\(next) 00:00:00"), ml: 50),
            ])
            let s = Progression.compute(ledger: l, prefs: P(goal: 2000), now: now, calendar: e.cal)
            #expect(Array(s.week.suffix(3)).map(\.ml) == [10, 90, 50], "\(z.id) \(day)")
        }
    }

    @Test(arguments: Zone.midnight)
    func firstInstantOfAGapDayBelongsToThatDay(_ z: Zone) {
        let e = Env(z.id)
        let gapStart = e.cal.startOfDay(for: e.d("\(z.spring) 12:00"))      // 01:00 where 00:xx does not exist
        let now = e.d("\(z.springNext) 12:00")
        let l = Ledger(startedAt: e.d("\(z.springEve) 08:00"), drinks: [
            Drink(at: gapStart.addingTimeInterval(-1), ml: 10),
            Drink(at: gapStart, ml: 20),
            Drink(at: e.d("\(z.spring) 23:59:59"), ml: 40),
        ])
        let s = Progression.compute(ledger: l, prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(Array(s.week.suffix(3)).map(\.ml) == [10, 60, 0], "\(z.id)")
        #expect(s.week.map { e.cal.dayKey($0.day) } == (0..<7).map { civil(z.springNext, plus: $0 - 6) })
    }

    @Test func midnightThatDoesNotExistInTheZone() {
        // São Paulo skipped 00:00 on 2018-11-04 (clocks jumped 00:00 → 01:00): the local day starts at 01:00.
        let e = Env("America/Sao_Paulo")
        let now = e.d("2018-11-06 12:00")
        let l = Ledger(startedAt: e.d("2018-11-01 08:00"), drinks: (0..<6).map { Drink(at: e.d("\(civil("2018-11-01", plus: $0)) 12:00"), ml: 2000) })
        let s = Progression.compute(ledger: l, prefs: P(goal: 2000), now: now, calendar: e.cal)
        #expect(s.streak == 6)
        #expect(s.week.map { e.cal.dayKey($0.day) } == (0..<7).map { civil("2018-11-06", plus: $0 - 6) })
    }
}

// MARK: - Differential test against a straight-line reference of the spec

struct Ref {
    var xp = 0, streak = 0, best = 0, freezes = 0, totalML = 0, totalDrinks = 0, onCue = 0
    var todayML = 0, todayGoal = 0, atRisk = false
    var ach: Set<Achievement> = []
    var weekKeys: [String] = [], weekML: [Int] = []
    var goalOf: [String: Int] = [:]
}

/// Deliberately naive: civil dates are enumerated in UTC (immune to DST), weekdays come from the civil date.
func reference(_ ledger: Ledger, _ prefs: Prefs, _ now: Date, _ cal: Calendar) -> Ref {
    func key(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04ld-%02ld-%02ld", c.year!, c.month!, c.day!)
    }
    let valid = ledger.drinks.filter { $0.at <= now && $0.ml > 0 }.sorted { $0.at < $1.at }
    var byKey: [String: [Drink]] = [:]
    for d in valid { byKey[key(d.at), default: []].append(d) }
    let startKey = key(min(ledger.startedAt, valid.first?.at ?? ledger.startedAt))
    let todayKey = key(now)

    var r = Ref()
    var goal = ledger.goals.keys.min().map { ledger.goals[$0]! } ?? prefs.dailyGoalML
    var lost = 0
    var k = startKey
    while k <= todayKey {
        defer { k = civil(k, plus: 1) }
        let isToday = k == todayKey
        goal = max(1, isToday ? prefs.dailyGoalML : (ledger.goals[k] ?? goal))
        r.goalOf[k] = goal
        let ds = byKey[k] ?? []
        let total = ds.reduce(0) { $0 + $1.ml }
        r.xp += min(total, goal * 150 / 100) / 25
        for d in ds {
            r.totalDrinks += 1
            r.totalML += d.ml
            r.ach.insert(.firstSip)
            if d.onCue { r.onCue += 1; r.xp += 5 }
            if (5..<8).contains(cal.component(.hour, from: d.at)) { r.ach.insert(.earlyBird) }
        }
        if total >= goal {
            r.streak += 1
            r.xp += 50 + 5 * min(r.streak, 20)
            if r.streak % 7 == 0 { r.freezes = min(2, r.freezes + 1) }
            r.ach.insert(.goalGetter)
            if total * 100 >= goal * 150 { r.ach.insert(.overflow) }
            if lost >= 3 { r.ach.insert(.comeback) }
            lost = 0
        } else if !isToday {
            if !prefs.activeWeekdays.contains(civilWeekday(k)) {
                // off day: neutral
            } else if r.streak == 0 {
                // nothing to lose
            } else if r.freezes > 0 {
                r.freezes -= 1
            } else {
                lost = r.streak
                r.streak = 0
            }
        }
        r.best = max(r.best, r.streak)
        if isToday {
            r.todayML = total
            r.todayGoal = goal
            r.atRisk = r.streak > 0 && total < goal && prefs.activeWeekdays.contains(civilWeekday(k))
        }
    }
    if r.todayGoal == 0 { r.todayGoal = max(1, prefs.dailyGoalML) }
    if r.best >= 3 { r.ach.insert(.hatTrick) }
    if r.best >= 7 { r.ach.insert(.weekWarrior) }
    if r.best >= 14 { r.ach.insert(.fortnight) }
    if r.best >= 30 { r.ach.insert(.monsoon) }
    if r.onCue >= 10 { r.ach.insert(.quickDraw) }
    if r.onCue >= 100 { r.ach.insert(.reflexes) }
    if r.totalML >= 10_000 { r.ach.insert(.tenLiters) }
    if r.totalDrinks >= 100 { r.ach.insert(.centurion) }
    r.xp += r.ach.reduce(0) { $0 + $1.xp }
    r.weekKeys = (0..<7).map { civil(todayKey, plus: $0 - 6) }
    r.weekML = r.weekKeys.map { (byKey[$0] ?? []).reduce(0) { $0 + $1.ml } }
    return r
}

func randomLedger(_ g: inout SplitMix, _ e: Env, anchors: [String]) -> (Ledger, Prefs, Date) {
    let todayKey = anchors.randomElement(using: &g)!
    let now = e.d(todayKey).addingTimeInterval(TimeInterval(Int.random(in: 0..<86_400, using: &g)))
    let span = Int.random(in: -2...70, using: &g)
    let startDay = civil(todayKey, plus: -span)
    let startedAt = e.d(startDay).addingTimeInterval(TimeInterval(Int.random(in: 0..<82_800, using: &g)))

    var prefs = Prefs()
    prefs.dailyGoalML = [1, 500, 1000, 1001, 2000, 2500, 3333].randomElement(using: &g)!
    prefs.activeWeekdays = Double.random(in: 0..<1, using: &g) < 0.5 ? Set(1...7) : Set((1...7).filter { _ in Bool.random(using: &g) })

    var goals: [String: Int] = [:]
    for _ in 0..<Int.random(in: 0...4, using: &g) {
        goals[civil(startDay, plus: Int.random(in: -5...(max(span, 0) + 3), using: &g))] = [-20, 0, 1, 500, 1500, 2000, 2500, 3001].randomElement(using: &g)!
    }

    let totals = [0, 0, 300, 999, 1000, 1001, 1499, 1500, 1501, 1502, 2000, 2400, 2500, 3000, 3750, 3751, 5000]
    var drinks: [Drink] = []
    for off in -3...(max(span, 0) + 1) {
        let day = civil(startDay, plus: off)
        let base = e.d(day)
        let total = totals.randomElement(using: &g)!
        if total > 0 {
            let n = Int.random(in: 1...6, using: &g)
            for i in 0..<n {
                let ml = i == n - 1 ? total - (total / n) * (n - 1) : total / n
                var sec = Int.random(in: 0..<82_800, using: &g)
                let roll = Double.random(in: 0..<1, using: &g)
                if roll < 0.12 { sec = 0 } else if roll < 0.3 { sec = Int.random(in: 0..<28_800, using: &g) }
                drinks.append(Drink(at: base.addingTimeInterval(TimeInterval(sec)), ml: ml, onCue: Double.random(in: 0..<1, using: &g) < 0.4))
            }
        }
        if Double.random(in: 0..<1, using: &g) < 0.05 {
            drinks.append(Drink(at: base.addingTimeInterval(TimeInterval(Int.random(in: 0..<82_800, using: &g))), ml: [0, -5, -2000].randomElement(using: &g)!, onCue: true))
        }
    }
    return (Ledger(startedAt: startedAt, drinks: drinks, goals: goals), prefs, now)
}

func diff(_ s: Stats, _ r: Ref, _ cal: Calendar, now: Date) -> [String] {
    var out: [String] = []
    if let late = s.unlocked.first(where: { $0.value > now }) { out.append("achievement \(late.key) unlocked in the future: \(late.value)") }
    func chk<T: Equatable>(_ name: String, _ a: T, _ b: T) { if a != b { out.append("\(name): got \(a) want \(b)") } }
    chk("xp", s.xp, r.xp)
    chk("streak", s.streak, r.streak)
    chk("bestStreak", s.bestStreak, r.best)
    chk("freezes", s.freezes, r.freezes)
    chk("streakAtRisk", s.streakAtRisk, r.atRisk)
    chk("totalML", s.totalML, r.totalML)
    chk("totalDrinks", s.totalDrinks, r.totalDrinks)
    chk("onCueCount", s.onCueCount, r.onCue)
    chk("todayML", s.todayML, r.todayML)
    chk("todayGoal", s.todayGoal, r.todayGoal)
    chk("achievements", Set(s.unlocked.keys).sorted { $0.rawValue < $1.rawValue }.map(\.rawValue),
        r.ach.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue))
    chk("week keys", s.week.map { cal.dayKey($0.day) }, r.weekKeys)
    chk("week ml", s.week.map(\.ml), r.weekML)
    for (i, d) in s.week.enumerated() {
        if let g = r.goalOf[r.weekKeys[i]], d.goal != g { out.append("week[\(i)].goal: got \(d.goal) want \(g)") }
        if d.goal < 1 { out.append("week[\(i)].goal < 1") }
    }
    return out
}

@Suite("Progression · differential vs spec reference")
struct DifferentialTests {
    @Test(arguments: Zone.every)
    func randomLedgersAroundDST(_ z: Zone) {
        let e = Env(z.id)
        var g = SplitMix(1234)
        let anchors = (-4...4).map { civil(z.spring, plus: $0) } + (-4...4).map { civil(z.fall, plus: $0) }
            + (0..<10).map { civil("2026-03-01", plus: $0 * 30) }
        var failures: [String] = []
        for i in 0..<300 {
            let (ledger, prefs, now) = randomLedger(&g, e, anchors: anchors)
            let got = Progression.compute(ledger: ledger, prefs: prefs, now: now, calendar: e.cal)
            let want = reference(ledger, prefs, now, e.cal)
            let d = diff(got, want, e.cal, now: now)
            if !d.isEmpty {
                failures.append("#\(i) now=\(e.s(now)) started=\(e.s(ledger.startedAt)) goal=\(prefs.dailyGoalML) days=\(prefs.activeWeekdays.sorted()) goals=\(ledger.goals.sorted { $0.key < $1.key }) → \(d)")
            }
        }
        #expect(failures.isEmpty, "\(failures.count)/300 diverge, first: \(failures.prefix(3))")
    }

    @Test func longHistoryRandom() {
        let e = Env()
        var g = SplitMix(99)
        var failures: [String] = []
        for i in 0..<10 {
            let (generated, prefs, now) = randomLedger(&g, e, anchors: ["2026-06-10", "2026-11-23"])
            var ledger = generated
            ledger.startedAt = e.d(civil(e.cal.dayKey(now), plus: -(300 + i * 20)))
            let got = Progression.compute(ledger: ledger, prefs: prefs, now: now, calendar: e.cal)
            let want = reference(ledger, prefs, now, e.cal)
            let d = diff(got, want, e.cal, now: now)
            if !d.isEmpty { failures.append("#\(i): \(d)") }
        }
        #expect(failures.isEmpty, "\(failures.prefix(3))")
    }
}
