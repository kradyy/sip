import Testing
import Foundation
@testable import SipCore

@Suite("Prefs · decoding")
struct PrefsDecodingTests {
    func decode(_ json: String) throws -> Prefs { try JSONDecoder().decode(Prefs.self, from: Data(json.utf8)) }

    @Test func defaults() {
        let p = Prefs()
        #expect(p.intervalMinutes == 68)
        #expect(p.dailyGoalML == 1750)
        #expect(p.glassML == 219)
        #expect(p.activeFrom == 480)
        #expect(p.activeUntil == 1020)
        #expect(p.bottle == BottlePlan(ml: 1750, steps: 8))
        #expect(p.bottleOn)
        #expect(p.quietAfterGoal)
        #expect(p.activeWeekdays == Set(1...7))
        #expect(p.snoozeMinutes == 10)
        #expect(p.style == .fullscreen)
        #expect(p.sound == true)
    }

    @Test func emptyObjectDecodesToDefaults() throws {
        #expect(try decode("{}") == Prefs())
    }

    @Test func missingKeysFallBackPerField() throws {
        let p = try decode(#"{"dailyGoalML": 3000, "style": "banner"}"#)
        var want = Prefs()
        want.dailyGoalML = 3000
        want.style = .banner
        #expect(p == want)
    }

    @Test func unknownKeysAreIgnored() throws {
        #expect(try decode(#"{"somethingNew": [1,2,3], "intervalMinutes": 30}"#).intervalMinutes == 30)
    }

    @Test func wrongTypedFieldsFallBackIndividually() throws {
        let p = try decode("""
        {"intervalMinutes": "soon", "dailyGoalML": 3000, "glassML": null, "activeFrom": [1],
         "activeUntil": 1380, "activeWeekdays": "weekdays", "snoozeMinutes": 2.5,
         "style": "banner", "sound": false}
        """)
        #expect(p.intervalMinutes == Prefs().intervalMinutes)
        #expect(p.dailyGoalML == 3000)
        #expect(p.glassML == Prefs().glassML)
        #expect(p.activeFrom == 480)
        #expect(p.activeUntil == 1380)
        #expect(p.activeWeekdays == Set(1...7))
        #expect(p.snoozeMinutes == 10)
        #expect(p.style == .banner)
        #expect(p.sound == false)
    }

    @Test func wrongTypedSoundFallsBackToDefault() throws {
        #expect(try decode(#"{"sound": "loud", "dailyGoalML": 1800}"#).sound == true)
        #expect(try decode(#"{"sound": {}, "dailyGoalML": 1800}"#).dailyGoalML == 1800)
    }

    @Test func unknownStyleFallsBack() throws {
        let p = try decode(#"{"style": "neon", "intervalMinutes": 20}"#)
        #expect(p.style == .fullscreen)
        #expect(p.intervalMinutes == 20)
    }

    @Test func badWeekdayElementFallsBackToDefaultSet() throws {
        let p = try decode(#"{"activeWeekdays": [2, "x"], "glassML": 330}"#)
        #expect(p.activeWeekdays == Set(1...7))
        #expect(p.glassML == 330)
    }

    @Test func outOfRangeNumberFallsBack() throws {
        #expect(try decode(#"{"intervalMinutes": 1e30, "glassML": 400}"#).intervalMinutes == Prefs().intervalMinutes)
        #expect(try decode(#"{"intervalMinutes": 1e30, "glassML": 400}"#).glassML == 400)
    }

    @Test func plistDecodingToleratesMissingKeysToo() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["dailyGoalML": 1999, "sound": "nope"], format: .xml, options: 0)
        let p = try PropertyListDecoder().decode(Prefs.self, from: data)
        #expect(p.dailyGoalML == 1999)
        #expect(p.sound == true)
    }
}

@Suite("Prefs · round trip")
struct PrefsRoundTripTests {
    static func custom() -> Prefs {
        var p = Prefs()
        p.intervalMinutes = 17
        p.dailyGoalML = 3100
        p.glassML = 333
        p.activeFrom = 7 * 60 + 15
        p.activeUntil = 23 * 60 + 45
        p.activeWeekdays = [2, 4, 6]
        p.snoozeMinutes = 3
        p.style = .banner
        p.sound = false
        return p
    }

    @Test func jsonRoundTrip() throws {
        for p in [Prefs(), Self.custom()] {
            let data = try JSONEncoder().encode(p)
            #expect(try JSONDecoder().decode(Prefs.self, from: data) == p)
        }
    }

    @Test func sortedKeysJsonRoundTrip() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try enc.encode(Self.custom())
        #expect(try JSONDecoder().decode(Prefs.self, from: data) == Self.custom())
    }

    @Test func plistRoundTrip() throws {
        let data = try PropertyListEncoder().encode(Self.custom())
        #expect(try PropertyListDecoder().decode(Prefs.self, from: data) == Self.custom())
    }

    @Test func emptyWeekdaySetSurvives() throws {
        var p = Prefs()
        p.activeWeekdays = []
        let data = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(Prefs.self, from: data).activeWeekdays == [])
    }

    @Test func reminderStateRoundTrip() throws {
        let s = ReminderState(anchor: Date(timeIntervalSince1970: 1_800_000_000),
                              snoozedUntil: Date(timeIntervalSince1970: 1_800_000_600), pausedUntil: nil)
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(ReminderState.self, from: data) == s)
    }
}

@Suite("Calendar · dayKey")
struct DayKeyTests {
    @Test func zeroPadded() {
        let e = Env()
        #expect(e.cal.dayKey(e.d("2026-01-05 10:00")) == "2026-01-05")
        #expect(e.cal.dayKey(e.d("2026-10-05 10:00")) == "2026-10-05")
        #expect(e.cal.dayKey(e.d("2026-12-31 23:59:59")) == "2026-12-31")
        #expect(e.cal.dayKey(e.d("2027-01-01 00:00:00")) == "2027-01-01")
        #expect(e.cal.dayKey(e.d("2028-02-29 12:00")) == "2028-02-29")
    }

    @Test func yearIsPaddedToFourDigits() {
        let e = Env("UTC")
        let d = e.cal.date(from: DateComponents(year: 999, month: 3, day: 7, hour: 12))!
        #expect(e.cal.dayKey(d) == "0999-03-07")
        let d2 = e.cal.date(from: DateComponents(year: 12, month: 11, day: 1, hour: 12))!
        #expect(e.cal.dayKey(d2) == "0012-11-01")
    }

    @Test func usesTheCalendarsTimeZone() {
        // 2026-06-01T22:30:00Z is 00:30 on June 2nd in Stockholm and 18:30 on June 1st in New York.
        let instant = Date(timeIntervalSince1970: 1_780_353_000)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(utc.dateComponents([.hour, .minute, .day], from: instant).hour == 22)
        #expect(Env("Europe/Stockholm").cal.dayKey(instant) == "2026-06-02")
        #expect(Env("America/New_York").cal.dayKey(instant) == "2026-06-01")
        #expect(Env("Pacific/Auckland").cal.dayKey(instant) == "2026-06-02")
        #expect(utc.dayKey(instant) == "2026-06-01")
    }

    @Test func localMidnightBelongsToTheNewDay() {
        let e = Env()
        #expect(e.cal.dayKey(e.d("2026-06-02 00:00:00")) == "2026-06-02")
        #expect(e.cal.dayKey(e.d("2026-06-02 00:00:00").addingTimeInterval(-1)) == "2026-06-01")
    }

    @Test(arguments: Zone.all)
    func dstDaysAreSingleKeys(_ z: Zone) {
        let e = Env(z.id)
        for day in [z.spring, z.fall] {
            #expect(e.cal.dayKey(e.d("\(day) 00:00:00")) == day)
            #expect(e.cal.dayKey(e.d("\(day) 23:59:59")) == day)
            #expect(e.cal.dayKey(e.d("\(civil(day, plus: 1)) 00:00:00").addingTimeInterval(-1)) == day)
        }
        let first = e.d("\(z.fall) 01:30:00")        // ambiguous hour, both passes
        #expect(e.cal.dayKey(first) == z.fall)
        #expect(e.cal.dayKey(first.addingTimeInterval(3600)) == z.fall)
    }

    @Test(arguments: ["ar_SA", "fa_IR", "th_TH", "hi_IN", "ja_JP@calendar=japanese"])
    func localeIndependent(_ locale: String) {
        var cal = Env().cal
        cal.locale = Locale(identifier: locale)
        #expect(cal.dayKey(Env().d("2026-06-01 12:00")) == "2026-06-01")
    }
}

@Suite("Level")
struct LevelTests {
    @Test func firstThresholds() {
        #expect(Level.threshold(1) == 0)
        #expect(Level.threshold(2) == 100)
        #expect(Level.threshold(3) == 300)
        #expect(Level.threshold(4) == 600)
        #expect(Level.threshold(5) == 1000)
    }

    @Test func thresholdFormula() {
        for n in 1...200 { #expect(Level.threshold(n) == 50 * n * (n - 1), "n=\(n)") }
    }

    @Test func boundariesUpTo200() {
        for n in 1...200 {
            #expect(Level.level(forXP: Level.threshold(n)) == n, "xp = threshold(\(n))")
            #expect(Level.level(forXP: Level.threshold(n + 1) - 1) == n, "xp = threshold(\(n + 1)) - 1")
            if n > 1 { #expect(Level.level(forXP: Level.threshold(n) - 1) == n - 1, "xp = threshold(\(n)) - 1") }
            #expect(Level.level(forXP: Level.threshold(n) + 1) == n, "xp = threshold(\(n)) + 1")
        }
    }

    @Test func everyXPInTheFirstLevelsMapsToTheRightLevel() {
        var expected = 1
        for xp in 0...Level.threshold(60) {
            while Level.threshold(expected + 1) <= xp { expected += 1 }
            if Level.level(forXP: xp) != expected {
                Issue.record("xp \(xp): got \(Level.level(forXP: xp)), want \(expected)")
                break
            }
        }
    }

    @Test(arguments: [1_000, 10_000, 123_456, 1_000_000, 30_000_000, 100_000_000])
    func largeLevelsSurviveFloatingPointError(_ n: Int) {
        #expect(Level.level(forXP: Level.threshold(n)) == n)
        #expect(Level.level(forXP: Level.threshold(n) - 1) == n - 1)
        #expect(Level.level(forXP: Level.threshold(n + 1) - 1) == n)
    }

    @Test func negativeAndZeroXPIsLevelOne() {
        for xp in [0, -1, -100, -1_000_000, Int.min] { #expect(Level.level(forXP: xp) == 1, "xp \(xp)") }
    }

    @Test func titlesNeverCrash() {
        for l in [-5, 0, 1, 2, 14, 15, 1000] { #expect(!Level.title(l).isEmpty, "level \(l)") }
        #expect(Level.title(1) == "Dry Sponge")
        #expect(Level.title(14) == "Poseidon")
        #expect(Level.title(500) == "Poseidon")
    }

    @Test func statsDerivedValues() {
        var s = Stats()
        s.xp = 150
        #expect(s.level == 2)
        #expect(s.levelFloorXP == 100)
        #expect(s.nextLevelXP == 300)
        #expect(s.levelFraction == 0.25)
        s.todayGoal = 2000
        s.todayML = 500
        #expect(s.todayFraction == 0.25)
        #expect(s.remainingML == 1500)
        #expect(s.goalMet == false)
        s.todayML = 2500
        #expect(s.remainingML == 0)
        #expect(s.goalMet == true)
        #expect(Stats().todayFraction == 0)       // no division by zero
        #expect(Stats().goalMet == false)
    }
}

@Suite("Bottle plan")
struct BottlePlanTests {
    @Test func portionRoundsUpSoEveryStepFinishesTheBottle() {
        #expect(BottlePlan(ml: 1750, steps: 8).portionML == 219)
        #expect(BottlePlan(ml: 1600, steps: 8).portionML == 200)
        #expect(BottlePlan(ml: 1750, steps: 8).portionML * 8 >= 1750)
        #expect(BottlePlan(ml: 1750, steps: 0).portionML == 1750)
    }

    @Test func stepsDoneCountsWholeStepsCapped() {
        let b = BottlePlan(ml: 1750, steps: 8)
        #expect(b.stepsDone(0) == 0)
        #expect(b.stepsDone(218) == 0)
        #expect(b.stepsDone(219) == 1)
        #expect(b.stepsDone(1749) == 7)
        #expect(b.stepsDone(1750) == 8)   // the whole bottle counts as every step
        #expect(b.stepsDone(1752) == 8)
        #expect(b.stepsDone(5000) == 8)
    }

    @Test func defaultPresetIs1750In8StepsBetween8And17() {
        let p = Prefs()
        #expect(p.dailyGoalML == 1750)
        #expect(p.glassML == 219)
        #expect(p.intervalMinutes == 68)
        #expect(p.activeMinutes == 540)
    }

    @Test func turningThePlanOffSurvivesARoundTrip() throws {
        var p = Prefs()
        p.bottleOn = false
        p.intervalMinutes = 30
        let back = try JSONDecoder().decode(Prefs.self, from: JSONEncoder().encode(p))
        #expect(back.bottleOn == false)
        var applied = back
        applied.applyBottle()
        #expect(applied.intervalMinutes == 30)
    }

    /// Simulates someone answering every reminder the moment it appears: exactly `steps` reminders,
    /// all inside the window, and the bottle is finished.
    static let plans: [(Int, Int, Int, Int)] = [(1750, 8, 480, 1020), (2000, 6, 540, 1080), (1500, 10, 420, 1380), (1000, 4, 1320, 120)]

    @Test(arguments: plans)
    func everyStepFitsTheWindow(_ ml: Int, _ steps: Int, _ from: Int, _ until: Int) {
        let e = Env()
        var p = Prefs()
        p.activeFrom = from
        p.activeUntil = until
        p.bottle = BottlePlan(ml: ml, steps: steps)
        p.applyBottle()
        // One window: from just before it opens until 24 h later (overnight windows included).
        let opens = e.cal.date(bySettingHour: from / 60, minute: from % 60, second: 0, of: e.d("2026-06-10 00:00"))!
        var state = ReminderState(anchor: opens.addingTimeInterval(-86_400))
        var drank = 0
        var fired: [Date] = []
        var now = opens.addingTimeInterval(-60)
        while let next = p.nextReminder(state, now: now, calendar: e.cal, goalMet: drank >= p.dailyGoalML),
              next < opens.addingTimeInterval(86_400 - 60), fired.count < 50 {
            fired.append(next)
            drank += p.glassML
            state.restart(at: next)
            now = next
        }
        #expect(fired.count == steps, "\(ml)/\(steps) \(from)-\(until): \(fired)")
        #expect(fired.allSatisfy { p.isActive(at: $0, calendar: e.cal) })
        #expect(drank >= ml)
    }

    @Test func quietAfterGoalHoldsUntilTomorrowsWindow() {
        let e = Env()
        let p = Prefs()   // 08:00–17:00
        let s = ReminderState(anchor: e.d("2026-06-10 11:00"))
        #expect(p.nextReminder(s, now: e.d("2026-06-10 11:00"), calendar: e.cal, goalMet: true) == e.d("2026-06-11 08:00"))
        #expect(p.nextReminder(s, now: e.d("2026-06-10 11:00"), calendar: e.cal, goalMet: false) == e.d("2026-06-10 12:08"))
        var loud = p
        loud.quietAfterGoal = false
        #expect(loud.nextReminder(s, now: e.d("2026-06-10 11:00"), calendar: e.cal, goalMet: true) == e.d("2026-06-10 12:08"))
    }
}

@Suite("Robustness · absurd bottle values")
struct AbsurdBottleTests {
    static let plans: [(Int, Int)] = [(Int.max, 8), (1750, Int.max), (Int.min, Int.min), (1750, -5), (1750, 0), (0, 8)]

    @Test(arguments: plans)
    func neverTrapsAndStaysSane(_ ml: Int, _ steps: Int) {
        let b = BottlePlan(ml: ml, steps: steps)
        #expect((1...48).contains(b.safeSteps))
        #expect((1...20_000).contains(b.safeML))
        #expect(b.portionML >= 1)
        #expect((0...b.safeSteps).contains(b.stepsDone(Int.max)))
        var p = Prefs()
        p.bottle = b
        p.applyBottle()
        #expect(p.intervalMinutes >= 5 && p.glassML >= 1 && p.dailyGoalML >= 1)
    }
}

@Suite("Bottle plan · check-in buttons")
struct CheckInAmountTests {
    func prefs(choices: Int, bottleOn: Bool = true, ml: Int = 1750, steps: Int = 8) -> Prefs {
        var p = Prefs()
        p.bottle = BottlePlan(ml: ml, steps: steps, choices: choices)
        p.bottleOn = bottleOn
        p.applyBottle()
        return p
    }

    @Test func defaultIsOneButtonWithTheSip() {
        #expect(Prefs().bottle.choices == 1)
        #expect(Prefs().checkInAmounts == [219])
    }

    @Test func choicesAddAmountsAfterTheSip() {
        #expect(prefs(choices: 2).checkInAmounts == [219, 150])
        #expect(prefs(choices: 3).checkInAmounts == [219, 150, 330])
        #expect(prefs(choices: 4).checkInAmounts == [219, 150, 330, 500])
    }

    @Test(arguments: [0, -3, Int.min])
    func tooFewClampsToOne(choices: Int) {
        #expect(prefs(choices: choices).checkInAmounts == [219])
    }

    @Test(arguments: [5, 99, Int.max])
    func tooManyClampsToFour(choices: Int) {
        #expect(prefs(choices: choices).checkInAmounts.count == 4)
    }

    @Test func sipMatchingAPresetIsNotListedTwice() {
        // 1500 ml in 3 sips → 500 ml per sip, which is also a preset.
        #expect(prefs(choices: 4, ml: 1500, steps: 3).checkInAmounts == [500, 150, 330])
    }

    @Test func withoutABottleEveryAmountIsOffered() {
        var p = prefs(choices: 1, bottleOn: false)
        p.glassML = 250
        #expect(p.checkInAmounts == [250, 150, 330, 500])
    }

    @Test func oldSaveWithoutChoicesKeepsTheBottle() throws {
        let json = #"{"bottle":{"ml":2000,"steps":5},"bottleOn":true}"#
        let p = try JSONDecoder().decode(Prefs.self, from: Data(json.utf8))
        #expect(p.bottle == BottlePlan(ml: 2000, steps: 5, choices: 1))
    }

    @Test func badChoicesValueKeepsTheBottle() throws {
        let json = #"{"bottle":{"ml":2000,"steps":5,"choices":"lots"},"bottleOn":true}"#
        let p = try JSONDecoder().decode(Prefs.self, from: Data(json.utf8))
        #expect(p.bottle == BottlePlan(ml: 2000, steps: 5, choices: 1))
    }

    @Test func choicesRoundTrip() throws {
        let p = prefs(choices: 3)
        let back = try JSONDecoder().decode(Prefs.self, from: JSONEncoder().encode(p))
        #expect(back.bottle.choices == 3)
    }
}

@Suite("Bottle plan · custom glass")
struct CustomGlassTests {
    func prefs(glass: Int?, ml: Int = 1750, steps: Int = 8) -> Prefs {
        var p = Prefs()
        p.bottle = BottlePlan(ml: ml, steps: steps, customGlassML: glass)
        p.applyBottle()
        return p
    }

    @Test func defaultGlassIsOneSip() {
        #expect(Prefs().bottle.customGlassML == nil)
        #expect(Prefs().glassML == 219)
    }

    @Test func pickedGlassIsLoggedAndOffered() {
        let p = prefs(glass: 250)
        #expect(p.glassML == 250)
        #expect(p.checkInAmounts == [250])
    }

    @Test func pickedGlassKeepsGoalAndInterval() {
        let p = prefs(glass: 330)
        #expect(p.dailyGoalML == 1750)
        #expect(p.intervalMinutes == 68)
    }

    @Test func pickedGlassSurvivesBottleChanges() {
        #expect(prefs(glass: 250, ml: 2000, steps: 6).glassML == 250)
    }

    @Test func automaticGlassFollowsTheBottle() {
        #expect(prefs(glass: nil, ml: 2000, steps: 5).glassML == 400)
    }

    @Test(arguments: [(0, 1), (-50, 1), (Int.min, 1), (6000, 5000), (Int.max, 5000)])
    func absurdGlassIsClamped(glass: Int, expected: Int) {
        #expect(prefs(glass: glass).glassML == expected)
    }

    @Test func turningTheBottleOffKeepsTheGlass() {
        var p = prefs(glass: 330)
        p.bottleOn = false
        p.applyBottle()
        #expect(p.glassML == 330)
    }

    @Test func customGlassRoundTripsAndOldFilesStayAutomatic() throws {
        let back = try JSONDecoder().decode(Prefs.self, from: JSONEncoder().encode(prefs(glass: 300)))
        #expect(back.bottle.customGlassML == 300)
        let old = try JSONDecoder().decode(Prefs.self, from: Data(#"{"bottle":{"ml":1750,"steps":8}}"#.utf8))
        #expect(old.bottle.customGlassML == nil)
        #expect(old.glassML == 219)
    }
}

@Suite("Snooze off")
struct SnoozeOffTests {
    @Test(arguments: [(10, true), (1, true), (0, false), (-5, false), (Int.min, false)])
    func canSnooze(minutes: Int, expected: Bool) {
        var p = Prefs()
        p.snoozeMinutes = minutes
        #expect(p.canSnooze == expected)
    }

    @Test func defaultAllowsSnooze() { #expect(Prefs().canSnooze) }

    @Test func offSurvivesSaving() throws {
        var p = Prefs()
        p.snoozeMinutes = 0
        let back = try JSONDecoder().decode(Prefs.self, from: JSONEncoder().encode(p))
        #expect(back.snoozeMinutes == 0)
        #expect(!back.canSnooze)
    }
}
