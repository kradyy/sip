import Testing
import Foundation
@testable import SipCore

// 2026-06-01 is a Monday: Mon 1, Tue 2, Wed 3, Thu 4, Fri 5, Sat 6, Sun 7, Mon 8 …
// Weekday numbers: 1 = Sun, 2 = Mon … 6 = Fri, 7 = Sat.

@Suite("Schedule · window(on:)")
struct WindowTests {
    let e = Env()

    @Test func calendarSanity() {
        #expect(e.cal.component(.weekday, from: e.d("2026-06-01")) == 2)
        #expect(e.cal.component(.weekday, from: e.d(Zone.all[0].spring)) == 1)
        #expect(e.cal.component(.weekday, from: e.d(Zone.all[0].fall)) == 1)
    }

    @Test func sameDayWindow() {
        let w = P(hm(8), hm(22)).window(on: e.d("2026-06-01 15:00"), calendar: e.cal)
        #expect(e.s(w?.start) == "2026-06-01 08:00:00")
        #expect(e.s(w?.end) == "2026-06-01 22:00:00")
    }

    @Test(arguments: ["2026-06-01 00:00:00", "2026-06-01 07:59:59", "2026-06-01 23:59:59"])
    func anyInstantOfTheDayPicksThatDaysWindow(_ at: String) {
        let w = P().window(on: e.d(at), calendar: e.cal)
        #expect(e.s(w?.start) == "2026-06-01 08:00:00")
        #expect(e.s(w?.end) == "2026-06-01 22:00:00")
    }

    @Test func overnightWindowEndsNextDay() {
        let w = P(hm(22), hm(6)).window(on: e.d("2026-06-01"), calendar: e.cal)
        #expect(e.s(w?.start) == "2026-06-01 22:00:00")
        #expect(e.s(w?.end) == "2026-06-02 06:00:00")
    }

    @Test func overnightEndingAtMidnightSharp() {
        let w = P(hm(22), 0).window(on: e.d("2026-06-01"), calendar: e.cal)
        #expect(e.s(w?.start) == "2026-06-01 22:00:00")
        #expect(e.s(w?.end) == "2026-06-02 00:00:00")
    }

    @Test func equalFromUntilIs24hStartingAtFrom() {
        let w = P(hm(9), hm(9)).window(on: e.d("2026-06-01"), calendar: e.cal)
        #expect(e.s(w?.start) == "2026-06-01 09:00:00")
        #expect(e.s(w?.end) == "2026-06-02 09:00:00")
        #expect(abs((w?.duration ?? 0) - 86_400) < 0.001)
    }

    @Test func equalAtMidnightIsTheWholeCalendarDay() {
        let w = P(0, 0).window(on: e.d("2026-06-01"), calendar: e.cal)
        #expect(e.s(w?.start) == "2026-06-01 00:00:00")
        #expect(e.s(w?.end) == "2026-06-02 00:00:00")
    }

    @Test func windowStartingExactlyAtMidnight() {
        let w = P(0, hm(8)).window(on: e.d("2026-06-01 17:00"), calendar: e.cal)
        #expect(e.s(w?.start) == "2026-06-01 00:00:00")
        #expect(e.s(w?.end) == "2026-06-01 08:00:00")
    }

    @Test func untilOf1440MeansEndOfDay() {
        let w = P(hm(8), 1440).window(on: e.d("2026-06-01"), calendar: e.cal)
        #expect(e.s(w?.start) == "2026-06-01 08:00:00")
        #expect(e.s(w?.end) == "2026-06-02 00:00:00")
    }

    @Test func minutePrecision() {
        let w = P(hm(7, 45), hm(21, 15)).window(on: e.d("2026-06-01"), calendar: e.cal)
        #expect(e.s(w?.start) == "2026-06-01 07:45:00")
        #expect(e.s(w?.end) == "2026-06-01 21:15:00")
    }

    @Test func disabledWeekdayHasNoWindow() {
        let p = P(days: Set(1...7).subtracting([2]))      // Monday off
        #expect(p.window(on: e.d("2026-06-01"), calendar: e.cal) == nil)
        #expect(p.window(on: e.d("2026-06-01 23:59:59"), calendar: e.cal) == nil)
        #expect(p.window(on: e.d("2026-06-02"), calendar: e.cal) != nil)
    }

    @Test func weekdayIsCheckedOnTheDayTheWindowOpens() {
        let p = P(hm(22), hm(6), days: Set(1...7).subtracting([7]))   // Saturday off, overnight window
        let fri = p.window(on: e.d("2026-06-05"), calendar: e.cal)    // opens Friday, ends Saturday 06:00 even though Saturday is off
        #expect(e.s(fri?.start) == "2026-06-05 22:00:00")
        #expect(e.s(fri?.end) == "2026-06-06 06:00:00")
        #expect(p.window(on: e.d("2026-06-06"), calendar: e.cal) == nil)
        let sun = p.window(on: e.d("2026-06-07"), calendar: e.cal)
        #expect(e.s(sun?.start) == "2026-06-07 22:00:00")
    }

    @Test func noWeekdaysEnabledMeansNoWindow() {
        let p = P(days: [])
        for day in 1...7 { #expect(p.window(on: e.d("2026-06-0\(day)"), calendar: e.cal) == nil) }
    }

    @Test(arguments: Zone.every)
    func opensAtConfiguredWallClockOnDSTDays(_ z: Zone) {
        let e = Env(z.id)
        for day in [z.springEve, z.spring, z.springNext, z.fallEve, z.fall, z.fallNext] {
            let w = P(hm(8), hm(22)).window(on: e.d(day), calendar: e.cal)
            #expect(e.s(w?.start) == "\(day) 08:00:00", "start on \(day) in \(z.id)")
            #expect(e.s(w?.end) == "\(day) 22:00:00", "end on \(day) in \(z.id)")
        }
    }

    @Test(arguments: Zone.all)
    func overnightWindowAcrossSpringForwardIsOneHourShorter(_ z: Zone) {
        let e = Env(z.id)
        let w = P(hm(22), hm(6)).window(on: e.d(z.springEve), calendar: e.cal)
        #expect(e.s(w?.start) == "\(z.springEve) 22:00:00")
        #expect(e.s(w?.end) == "\(z.spring) 06:00:00")
        #expect(abs((w?.duration ?? 0) - 7 * 3600) < 0.001)
    }

    @Test(arguments: Zone.all)
    func overnightWindowAcrossFallBackIsOneHourLonger(_ z: Zone) {
        let e = Env(z.id)
        let w = P(hm(22), hm(6)).window(on: e.d(z.fallEve), calendar: e.cal)
        #expect(e.s(w?.start) == "\(z.fallEve) 22:00:00")
        #expect(e.s(w?.end) == "\(z.fall) 06:00:00")
        #expect(abs((w?.duration ?? 0) - 9 * 3600) < 0.001)
    }

    @Test(arguments: Zone.all)
    func twentyFourHourWindowEndsAtSameWallClockNextDayOnDST(_ z: Zone) {
        let e = Env(z.id)
        let w = P(hm(9), hm(9)).window(on: e.d(z.spring), calendar: e.cal)
        #expect(e.s(w?.start) == "\(z.spring) 09:00:00")
        #expect(e.s(w?.end) == "\(z.springNext) 09:00:00")
    }

    /// Spec is silent when the configured opening time does not exist; we only demand a sane, same-day, non-nil window.
    @Test func openingTimeInsideSpringForwardGap() {
        let z = Zone.all[0]
        let e = Env(z.id)
        let w = P(hm(2, 30), hm(22)).window(on: e.d(z.spring), calendar: e.cal)
        #expect(w != nil)
        if let w {
            #expect(e.cal.dayKey(w.start) == z.spring)
            #expect(e.cal.component(.hour, from: w.start) == 3)   // pushed forward past the gap
            #expect(e.s(w.end) == "\(z.spring) 22:00:00")
        }
    }
}

@Suite("Schedule · nextActiveInstant")
struct NextActiveInstantTests {
    let e = Env()

    func next(_ p: Prefs, _ t: String) -> String { e.s(p.nextActiveInstant(atOrAfter: e.d(t), calendar: e.cal)) }

    @Test(arguments: [
        ("2026-06-01 00:00:00", "2026-06-01 08:00:00"),
        ("2026-06-01 07:59:59", "2026-06-01 08:00:00"),
        ("2026-06-01 08:00:00", "2026-06-01 08:00:00"),     // exactly at start: inside
        ("2026-06-01 12:00:30", "2026-06-01 12:00:30"),
        ("2026-06-01 21:59:59", "2026-06-01 21:59:59"),
        ("2026-06-01 22:00:00", "2026-06-02 08:00:00"),     // end is exclusive
        ("2026-06-01 23:59:59", "2026-06-02 08:00:00"),
        ("2026-06-02 00:00:00", "2026-06-02 08:00:00"),
    ])
    func plainDaytimeWindow(_ t: String, _ expected: String) {
        #expect(next(P(), t) == expected)
    }

    @Test(arguments: [
        ("2026-06-05 21:59:00", "2026-06-05 21:59:00"),
        ("2026-06-05 22:00:00", "2026-06-08 08:00:00"),     // Friday evening → Monday
        ("2026-06-06 12:00:00", "2026-06-08 08:00:00"),
        ("2026-06-07 23:59:59", "2026-06-08 08:00:00"),
        ("2026-06-08 07:59:59", "2026-06-08 08:00:00"),
    ])
    func weekendGap(_ t: String, _ expected: String) {
        #expect(next(P(days: [2, 3, 4, 5, 6]), t) == expected)
    }

    @Test(arguments: [
        ("2026-06-01 21:59:59", "2026-06-01 22:00:00"),
        ("2026-06-01 22:00:00", "2026-06-01 22:00:00"),
        ("2026-06-01 23:59:59", "2026-06-01 23:59:59"),
        ("2026-06-02 00:00:00", "2026-06-02 00:00:00"),     // yesterday's window still open
        ("2026-06-02 03:00:00", "2026-06-02 03:00:00"),
        ("2026-06-02 05:59:59", "2026-06-02 05:59:59"),
        ("2026-06-02 06:00:00", "2026-06-02 22:00:00"),     // overnight end exclusive
        ("2026-06-02 12:00:00", "2026-06-02 22:00:00"),
    ])
    func overnightWindowCoversEarlyMorning(_ t: String, _ expected: String) {
        #expect(next(P(hm(22), hm(6)), t) == expected)
    }

    @Test(arguments: [
        ("2026-06-01 08:00:00", "2026-06-05 22:00:00"),     // Mon → first Friday
        ("2026-06-05 21:00:00", "2026-06-05 22:00:00"),
        ("2026-06-05 23:00:00", "2026-06-05 23:00:00"),
        ("2026-06-06 03:00:00", "2026-06-06 03:00:00"),     // Saturday is off but Friday's window runs into it
        ("2026-06-06 05:59:59", "2026-06-06 05:59:59"),
        ("2026-06-06 06:00:00", "2026-06-12 22:00:00"),
        ("2026-06-06 12:00:00", "2026-06-12 22:00:00"),
        ("2026-06-07 03:00:00", "2026-06-12 22:00:00"),     // Sunday morning: nothing covers it
    ])
    func overnightWindowCrossingIntoDisabledWeekday(_ t: String, _ expected: String) {
        #expect(next(P(hm(22), hm(6), days: [6]), t) == expected)
    }

    @Test(arguments: [
        ("2026-06-08 07:00:00", "2026-06-08 08:00:00"),
        ("2026-06-08 22:00:00", "2026-06-15 08:00:00"),     // a full week ahead
        ("2026-06-09 00:00:00", "2026-06-15 08:00:00"),
        ("2026-06-14 23:59:59", "2026-06-15 08:00:00"),
    ])
    func singleEnabledWeekdayLooksAWeekAhead(_ t: String, _ expected: String) {
        #expect(next(P(days: [2]), t) == expected)
    }

    @Test(arguments: [
        ("2026-06-08 23:00:00", "2026-06-08 23:00:00"),
        ("2026-06-09 05:59:59", "2026-06-09 05:59:59"),
        ("2026-06-09 06:00:00", "2026-06-15 22:00:00"),
        ("2026-06-08 22:00:00", "2026-06-08 22:00:00"),
    ])
    func singleDayOvernight(_ t: String, _ expected: String) {
        #expect(next(P(hm(22), hm(6), days: [2]), t) == expected)
    }

    @Test(arguments: [
        ("2026-06-08 09:00:00", "2026-06-08 09:00:00"),
        ("2026-06-09 08:59:59", "2026-06-09 08:59:59"),     // Monday's 24h window runs to Tuesday 09:00
        ("2026-06-09 09:00:00", "2026-06-15 09:00:00"),
        ("2026-06-08 08:59:59", "2026-06-08 09:00:00"),
    ])
    func twentyFourHourWindowOnOneWeekday(_ t: String, _ expected: String) {
        #expect(next(P(hm(9), hm(9), days: [2]), t) == expected)
    }

    @Test func twentyFourHourWindowOnAllDaysIsAlwaysActive() {
        let p = P(hm(9), hm(9))
        for t in ["2026-06-01 00:00:00", "2026-06-01 08:59:59", "2026-06-01 09:00:00", "2026-06-03 23:59:59"] {
            #expect(next(p, t) == t)
        }
    }

    @Test func nilOnlyWhenNoWeekdayEnabled() {
        let none = P(days: [])
        #expect(none.nextActiveInstant(atOrAfter: e.d("2026-06-01 12:00"), calendar: e.cal) == nil)
        for day in 1...7 {
            let p = P(days: [day])
            #expect(p.nextActiveInstant(atOrAfter: e.d("2026-06-03 12:00"), calendar: e.cal) != nil, "weekday \(day)")
            let overnight = P(hm(22), hm(6), days: [day])
            #expect(overnight.nextActiveInstant(atOrAfter: e.d("2026-06-03 12:00"), calendar: e.cal) != nil, "overnight \(day)")
        }
    }

    @Test func isActiveAgreesAtBoundaries() {
        let p = P()
        #expect(p.isActive(at: e.d("2026-06-01 07:59:59"), calendar: e.cal) == false)
        #expect(p.isActive(at: e.d("2026-06-01 08:00:00"), calendar: e.cal) == true)
        #expect(p.isActive(at: e.d("2026-06-01 21:59:59"), calendar: e.cal) == true)
        #expect(p.isActive(at: e.d("2026-06-01 22:00:00"), calendar: e.cal) == false)
        #expect(P(days: []).isActive(at: e.d("2026-06-01 12:00"), calendar: e.cal) == false)
    }

    @Test(arguments: Zone.all)
    func daytimeWindowOnDSTDays(_ z: Zone) {
        let e = Env(z.id)
        let p = P()
        func n(_ t: String) -> String { e.s(p.nextActiveInstant(atOrAfter: e.d(t), calendar: e.cal)) }
        for day in [z.spring, z.fall] {
            #expect(n("\(day) 00:30:00") == "\(day) 08:00:00")
            #expect(n("\(day) 07:59:59") == "\(day) 08:00:00")
            #expect(n("\(day) 12:00:00") == "\(day) 12:00:00")
            #expect(n("\(day) 22:00:00") == e.s(e.d("\(civil(day, plus: 1)) 08:00")))
        }
        #expect(n("\(z.springEve) 22:00:00") == "\(z.spring) 08:00:00")
        #expect(n("\(z.fallEve) 23:00:00") == "\(z.fall) 08:00:00")
        // The window opening instant must be the real 08:00 local one, not "midnight + 8h".
        let open = p.nextActiveInstant(atOrAfter: e.d("\(z.spring) 00:30:00"), calendar: e.cal)!
        #expect(e.cal.component(.hour, from: open) == 8)
        let openFall = p.nextActiveInstant(atOrAfter: e.d("\(z.fall) 00:30:00"), calendar: e.cal)!
        #expect(e.cal.component(.hour, from: openFall) == 8)
    }

    @Test(arguments: Zone.all)
    func overnightWindowOnDSTDays(_ z: Zone) {
        let e = Env(z.id)
        let p = P(hm(22), hm(6))
        func n(_ t: String) -> String { e.s(p.nextActiveInstant(atOrAfter: e.d(t), calendar: e.cal)) }
        for day in [z.spring, z.fall] {
            #expect(n("\(day) 05:59:59") == "\(day) 05:59:59")
            #expect(n("\(day) 06:00:00") == "\(day) 22:00:00")
            #expect(n("\(day) 12:00:00") == "\(day) 22:00:00")
        }
        // Fall-back day: the repeated hour is covered both times.
        let first = e.d("\(z.fall) 02:30:00")
        let again = first.addingTimeInterval(3600)
        #expect(p.nextActiveInstant(atOrAfter: first, calendar: e.cal) == first)
        #expect(p.nextActiveInstant(atOrAfter: again, calendar: e.cal) == again)
    }

    @Test(arguments: Zone.all)
    func overnightEndsAtWallClockSoLastInstantIsRealOnDSTDays(_ z: Zone) {
        let e = Env(z.id)
        let p = P(hm(22), hm(6))
        // One second before the wall-clock end is still active; the end itself is not.
        let end = e.d("\(z.spring) 06:00:00")
        #expect(p.isActive(at: end.addingTimeInterval(-1), calendar: e.cal))
        #expect(!p.isActive(at: end, calendar: e.cal))
        let endFall = e.d("\(z.fall) 06:00:00")
        #expect(p.isActive(at: endFall.addingTimeInterval(-1), calendar: e.cal))
        #expect(!p.isActive(at: endFall, calendar: e.cal))
    }

    @Test(arguments: Zone.all)
    func twentyFourHourWindowOnDSTDays(_ z: Zone) {
        let e = Env(z.id)
        let p = P(hm(9), hm(9))
        for day in [z.spring, z.fall] {
            for t in ["\(day) 00:30:00", "\(day) 08:59:59", "\(day) 09:00:00", "\(day) 23:59:59"] {
                #expect(p.nextActiveInstant(atOrAfter: e.d(t), calendar: e.cal) == e.d(t), "\(t)")
            }
        }
    }

    // MARK: Randomised differential check against a wall-clock oracle

    static func oracleMismatches(_ z: Zone, allowed: [Range<Int>], count: Int = 400, seed: UInt64 = 2026) -> [String] {
        let e = Env(z.id)
        var g = SplitMix(seed)
        var failures: [String] = []
        let anchors = (-3...3).map { civil(z.spring, plus: $0) } + (-3...3).map { civil(z.fall, plus: $0) }
            + ["2026-01-01", "2026-06-01", "2026-06-15", "2027-01-01"]
        for i in 0..<count {
            let p = randomPrefs(&g, allowed: allowed)
            let day = anchors.randomElement(using: &g)!
            // Start from noon-ish of the anchor day so the instant exists in every zone.
            let t = e.d("\(day) 05:00").addingTimeInterval(TimeInterval(Int.random(in: -4 * 3600..<(86_400 - 5 * 3600), using: &g)))
            let got = p.nextActiveInstant(atOrAfter: t, calendar: e.cal)
            let want = Oracle(e: e, p: p).next(t)
            if got != want {
                failures.append("#\(i) from=\(p.activeFrom) until=\(p.activeUntil) days=\(p.activeWeekdays.sorted()) t=\(e.s(t)) got=\(e.s(got)) want=\(e.s(want))")
            }
        }
        return failures
    }

    static func scanMismatches(_ z: Zone, configs: [Prefs]) -> [String] {
        let e = Env(z.id)
        var bad: [String] = []
        for p in configs {
            let oracle = Oracle(e: e, p: p)
            for day in [z.springEve, z.fallEve] {
                var t = e.d(day)
                for _ in 0..<(3 * 24 * 60) {
                    let got = p.nextActiveInstant(atOrAfter: t, calendar: e.cal)
                    let want = oracle.next(t)
                    if got != want { bad.append("from=\(p.activeFrom) until=\(p.activeUntil) days=\(p.activeWeekdays.sorted()) \(e.s(t)): got \(e.s(got)) want \(e.s(want))") }
                    t = t.addingTimeInterval(60)
                }
            }
        }
        return bad
    }

    @Test(arguments: Zone.all)
    func randomPrefsMatchWallClockOracle(_ z: Zone) {
        let failures = Self.oracleMismatches(z, allowed: [0..<60, 240..<1440])
        #expect(failures.isEmpty, "\(failures.count) mismatches, first: \(failures.prefix(5))")
    }

    @Test(arguments: Zone.midnight)
    func randomPrefsMatchWallClockOracleWhereDSTJumpsAtMidnight(_ z: Zone) {
        let failures = Self.oracleMismatches(z, allowed: [60..<1380])
        #expect(failures.isEmpty, "\(failures.count) mismatches, first: \(failures.prefix(5))")
    }

    @Test(arguments: Zone.all)
    func minuteByMinuteScanAcrossDSTMatchesOracle(_ z: Zone) {
        let bad = Self.scanMismatches(z, configs: [P(hm(22), hm(6)), P(hm(8), hm(22), days: [2, 3, 4, 5, 6]), P(hm(9), hm(9), days: [1, 4]), P(hm(20), hm(5), days: [1, 7])])
        #expect(bad.isEmpty, "\(bad.count) bad, first: \(bad.prefix(3))")
    }

    @Test(arguments: Zone.midnight)
    func minuteByMinuteScanWhereDSTJumpsAtMidnight(_ z: Zone) {
        let bad = Self.scanMismatches(z, configs: [P(hm(22), hm(6)), P(hm(8), hm(22), days: [2, 3, 4, 5, 6]), P(hm(9), hm(9), days: [1, 4]), P(hm(20), hm(5), days: [1, 7])])
        #expect(bad.isEmpty, "\(bad.count) bad, first: \(bad.prefix(3))")
    }

    /// Spec is silent on windows whose edge falls in the skipped midnight hour; we demand a sane window on the right day.
    @Test(arguments: Zone.midnight)
    func windowEdgesInTheSkippedMidnightHour(_ z: Zone) {
        let e = Env(z.id)
        let startsAtMidnight = P(0, hm(8)).window(on: e.d("\(z.spring) 12:00"), calendar: e.cal)
        #expect(startsAtMidnight != nil)
        if let w = startsAtMidnight {
            #expect(e.cal.dayKey(w.start) == z.spring)
            #expect(w.start == e.cal.startOfDay(for: e.d("\(z.spring) 12:00")))   // the first instant of the day that exists
            #expect(e.s(w.end) == "\(z.spring) 08:00:00")
        }
        let endsAtMidnight = P(hm(22), 0).window(on: e.d("\(z.springEve) 12:00"), calendar: e.cal)
        #expect(endsAtMidnight != nil)
        if let w = endsAtMidnight {
            #expect(e.s(w.start) == "\(z.springEve) 22:00:00")
            #expect(w.end == e.cal.startOfDay(for: e.d("\(z.spring) 12:00")))     // midnight == start of the next local day
            #expect(w.duration > 0 && w.duration <= 2 * 3600 + 0.001)
        }
        let allDay = P(0, 0).window(on: e.d("\(z.springEve) 12:00"), calendar: e.cal)
        #expect(allDay?.start == e.cal.startOfDay(for: e.d("\(z.springEve) 12:00")))
        #expect(allDay?.end == e.cal.startOfDay(for: e.d("\(z.spring) 12:00")))
        // Consecutive all-day windows must tile with no gap and no overlap.
        let nextDay = P(0, 0).window(on: e.d("\(z.spring) 12:00"), calendar: e.cal)
        #expect(nextDay?.start == allDay?.end)
    }
}

@Suite("Schedule · nextReminder")
struct NextReminderTests {
    let e = Env()

    func rem(_ p: Prefs, _ s: ReminderState, now: String) -> String {
        e.s(p.nextReminder(s, now: e.d(now), calendar: e.cal))
    }

    @Test func dueInsideWindow() {
        let s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        #expect(rem(P(), s, now: "2026-06-01 10:10") == "2026-06-01 10:45:00")
    }

    @Test func overdueWithinWindowFiresNow() {
        let s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        #expect(rem(P(), s, now: "2026-06-01 12:00:07") == "2026-06-01 12:00:07")
        #expect(rem(P(), s, now: "2026-06-01 10:45:00") == "2026-06-01 10:45:00")   // due == now → fire now
    }

    @Test(arguments: [
        ("2026-06-03 06:00:00", "2026-06-03 08:00:00"),     // slept through the night: wait for the window
        ("2026-06-03 00:00:00", "2026-06-03 08:00:00"),
        ("2026-06-03 07:59:59", "2026-06-03 08:00:00"),
        ("2026-06-03 08:00:00", "2026-06-03 08:00:00"),
        ("2026-06-03 21:59:59", "2026-06-03 21:59:59"),
        ("2026-06-03 22:00:00", "2026-06-04 08:00:00"),
        ("2026-06-03 23:30:00", "2026-06-04 08:00:00"),
    ])
    func anchorDaysInThePastNeverFiresOutsideWindow(_ now: String, _ expected: String) {
        let s = ReminderState(anchor: e.d("2026-06-01 15:00"))
        #expect(rem(P(), s, now: now) == expected)
    }

    @Test(arguments: [
        ("2026-06-01 07:00:00", "2026-06-01 08:00:00"),     // due 07:45, before the window
        ("2026-06-01 21:15:00", "2026-06-02 08:00:00"),     // due 22:00 exactly, end exclusive
        ("2026-06-01 21:30:00", "2026-06-02 08:00:00"),     // due 22:15
        ("2026-06-01 21:14:59", "2026-06-01 21:59:59"),     // due 21:59:59
        ("2026-06-01 21:15:01", "2026-06-02 08:00:00"),
    ])
    func dueAtWindowEdges(_ anchor: String, _ expected: String) {
        let s = ReminderState(anchor: e.d(anchor))
        #expect(rem(P(), s, now: anchor) == expected)
    }

    @Test func fridayEveningRollsToMonday() {
        let s = ReminderState(anchor: e.d("2026-06-05 21:30"))
        #expect(rem(P(days: [2, 3, 4, 5, 6]), s, now: "2026-06-05 21:40") == "2026-06-08 08:00:00")
    }

    @Test func snoozeReplacesAnchorPlusIntervalEvenWhenEarlier() {
        var s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        s.snooze(at: e.d("2026-06-01 10:00"), minutes: 5)
        #expect(rem(P(), s, now: "2026-06-01 10:01") == "2026-06-01 10:05:00")
    }

    @Test func snoozeLaterThanInterval() {
        var s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        s.snooze(at: e.d("2026-06-01 10:40"), minutes: 30)
        #expect(rem(P(), s, now: "2026-06-01 10:41") == "2026-06-01 11:10:00")
    }

    @Test func snoozeLandingAfterWindowEndRollsToNextOpening() {
        var s = ReminderState(anchor: e.d("2026-06-01 21:00"))
        s.snooze(at: e.d("2026-06-01 21:55"), minutes: 10)       // 22:05
        #expect(rem(P(), s, now: "2026-06-01 21:56") == "2026-06-02 08:00:00")
        var s2 = ReminderState(anchor: e.d("2026-06-01 21:00"))
        s2.snooze(at: e.d("2026-06-01 21:50"), minutes: 10)      // exactly 22:00
        #expect(rem(P(), s2, now: "2026-06-01 21:51") == "2026-06-02 08:00:00")
    }

    @Test func snoozeLandingBeforeWindowOpens() {
        var s = ReminderState(anchor: e.d("2026-06-01 22:30"))
        s.snooze(at: e.d("2026-06-01 22:30"), minutes: 10)
        #expect(rem(P(), s, now: "2026-06-01 22:31") == "2026-06-02 08:00:00")
    }

    @Test func expiredSnoozeFiresNowInsideWindow() {
        var s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        s.snooze(at: e.d("2026-06-01 10:00"), minutes: 5)
        #expect(rem(P(), s, now: "2026-06-01 11:00") == "2026-06-01 11:00:00")
    }

    @Test func pauseLaterThanDueWins() {
        var s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        s.pausedUntil = e.d("2026-06-01 15:00")
        #expect(rem(P(), s, now: "2026-06-01 10:10") == "2026-06-01 15:00:00")
    }

    @Test func pauseIgnoredWithSnoozeOff() {
        var s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        s.pausedUntil = e.d("2026-06-01 15:00")
        var p = P()
        p.snoozeMinutes = 0
        #expect(rem(p, s, now: "2026-06-01 10:10") == "2026-06-01 10:45:00")
    }

    @Test func pauseEarlierThanDueIsIgnored() {
        var s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        s.pausedUntil = e.d("2026-06-01 10:20")
        #expect(rem(P(), s, now: "2026-06-01 10:10") == "2026-06-01 10:45:00")
    }

    @Test func pauseInThePastIsIgnored() {
        var s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        s.pausedUntil = e.d("2026-05-01 10:00")
        #expect(rem(P(), s, now: "2026-06-01 10:10") == "2026-06-01 10:45:00")
        #expect(rem(P(), s, now: "2026-06-01 13:00") == "2026-06-01 13:00:00")
    }

    @Test func pauseEndingOutsideWindowRollsForward() {
        var s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        s.pausedUntil = e.d("2026-06-01 23:30")
        #expect(rem(P(), s, now: "2026-06-01 10:10") == "2026-06-02 08:00:00")
        s.pausedUntil = e.d("2026-06-02 03:00")
        #expect(rem(P(), s, now: "2026-06-01 10:10") == "2026-06-02 08:00:00")
    }

    @Test func pauseBeatsSnoozeWhenLater() {
        var s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        s.snooze(at: e.d("2026-06-01 10:00"), minutes: 10)
        s.pausedUntil = e.d("2026-06-01 12:00")
        #expect(rem(P(), s, now: "2026-06-01 10:05") == "2026-06-01 12:00:00")
    }

    @Test(arguments: [0, -1, -45, Int.min / 120])
    func nonPositiveIntervalIsOneMinute(_ interval: Int) {
        let s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        #expect(rem(P(interval: interval), s, now: "2026-06-01 10:00") == "2026-06-01 10:01:00")
    }

    @Test func longIntervalSpansDays() {
        let s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        #expect(rem(P(interval: 3 * 24 * 60), s, now: "2026-06-01 10:00") == "2026-06-04 10:00:00")
        #expect(rem(P(interval: 3 * 24 * 60 + 13 * 60), s, now: "2026-06-01 10:00") == "2026-06-05 08:00:00")   // lands at 23:00
    }

    @Test func noWeekdaysEnabledMeansNoReminder() {
        let s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        #expect(rem(P(days: []), s, now: "2026-06-01 10:10") == "nil")
    }

    @Test func restartKeepsPauseAndDropsSnooze() {
        var s = ReminderState(anchor: e.d("2026-06-01 10:00"),
                              snoozedUntil: e.d("2026-06-01 10:30"), pausedUntil: e.d("2026-06-01 14:00"))
        s.restart(at: e.d("2026-06-01 11:00"))
        #expect(s.anchor == e.d("2026-06-01 11:00"))
        #expect(s.snoozedUntil == nil)
        #expect(s.pausedUntil == e.d("2026-06-01 14:00"))
        #expect(rem(P(), s, now: "2026-06-01 11:00") == "2026-06-01 14:00:00")
    }

    @Test func restartThenInterval() {
        var s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        s.snooze(at: e.d("2026-06-01 10:00"), minutes: 5)
        s.restart(at: e.d("2026-06-01 10:02"))
        #expect(rem(P(), s, now: "2026-06-01 10:02") == "2026-06-01 10:47:00")
    }

    @Test(arguments: [(10, 600.0), (1, 60.0), (0, 60.0), (-3, 60.0), (Int.min / 120, 60.0), (90, 5400.0)])
    func snoozeMath(_ minutes: Int, _ seconds: Double) {
        var s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        let now = e.d("2026-06-01 10:00")
        s.snooze(at: now, minutes: minutes)
        #expect(s.snoozedUntil == now.addingTimeInterval(seconds))
    }

    @Test(arguments: Zone.all)
    func overdueAcrossDSTNightWaitsForWindow(_ z: Zone) {
        let e = Env(z.id)
        let p = P()
        let s = ReminderState(anchor: e.d("\(z.springEve) 21:00"))
        // 07:00 local on the spring-forward day (after the gap): still before the 08:00 opening.
        #expect(e.s(p.nextReminder(s, now: e.d("\(z.spring) 07:00"), calendar: e.cal)) == "\(z.spring) 08:00:00")
        let s2 = ReminderState(anchor: e.d("\(z.fallEve) 21:00"))
        #expect(e.s(p.nextReminder(s2, now: e.d("\(z.fall) 07:00"), calendar: e.cal)) == "\(z.fall) 08:00:00")
        // Due lands after the wall-clock close on a DST day.
        let s3 = ReminderState(anchor: e.d("\(z.spring) 21:30"))
        #expect(e.s(p.nextReminder(s3, now: e.d("\(z.spring) 21:31"), calendar: e.cal)) == "\(z.springNext) 08:00:00")
    }

    @Test(arguments: Zone.all)
    func randomStatesNeverFireOutsideWindowAndMatchSpecFormula(_ z: Zone) {
        let e = Env(z.id)
        var g = SplitMix(7)
        var failures: [String] = []
        let anchors = (-2...2).map { civil(z.spring, plus: $0) } + (-2...2).map { civil(z.fall, plus: $0) } + ["2026-06-01", "2026-06-20"]
        for i in 0..<400 {
            let p = randomPrefs(&g, emptyDaysChance: 0.05)
            var p2 = p
            p2.intervalMinutes = [-5, 0, 1, 7, 45, 90, 600, 3000].randomElement(using: &g)!
            let base = e.d(anchors.randomElement(using: &g)!)
            func rnd(_ range: ClosedRange<Int>) -> Date { base.addingTimeInterval(TimeInterval(Int.random(in: range, using: &g))) }
            let day = 86_400
            var s = ReminderState(anchor: rnd(-3 * day ... day))
            if Bool.random(using: &g) { s.snoozedUntil = rnd(-2 * day ... 2 * day) }
            if Bool.random(using: &g) { s.pausedUntil = rnd(-2 * day ... 2 * day) }
            let now = rnd(-day ... 2 * day)
            let got = p2.nextReminder(s, now: now, calendar: e.cal)

            var due = s.snoozedUntil ?? s.anchor.addingTimeInterval(TimeInterval(max(1, p2.intervalMinutes) * 60))
            if let paused = s.pausedUntil, paused > due { due = paused }
            let want = Oracle(e: e, p: p2).next(max(due, now))
            var why = ""
            if got != want { why = "got \(e.s(got)) want \(e.s(want))" }
            else if let got, got < now { why = "result before now" }
            else if let got, !Oracle(e: e, p: p2).active(got) { why = "result outside window" }
            if !why.isEmpty {
                failures.append("#\(i) from=\(p2.activeFrom) until=\(p2.activeUntil) days=\(p2.activeWeekdays.sorted()) int=\(p2.intervalMinutes) anchor=\(e.s(s.anchor)) snooze=\(e.s(s.snoozedUntil)) pause=\(e.s(s.pausedUntil)) now=\(e.s(now)): \(why)")
            }
        }
        #expect(failures.isEmpty, "\(failures.count) bad, first: \(failures.prefix(4))")
    }
}

// MARK: - Oracle and generators

/// Independent oracle: is an instant inside a window, judged purely from local wall-clock components?
/// Only meaningful when from/until avoid the 01:00-03:59 hours that DST can skip or repeat.
struct Oracle {
    let e: Env
    let p: Prefs

    func active(_ t: Date) -> Bool {
        let c = e.cal.dateComponents([.weekday, .hour, .minute], from: t)
        let m = c.hour! * 60 + c.minute!
        let wd = c.weekday!, prev = wd == 1 ? 7 : wd - 1
        let today = p.activeWeekdays.contains(wd), yesterday = p.activeWeekdays.contains(prev)
        if p.activeUntil > p.activeFrom { return today && m >= p.activeFrom && m < p.activeUntil }
        return (today && m >= p.activeFrom) || (yesterday && m < p.activeUntil)
    }

    func next(_ t: Date) -> Date? {
        guard !p.activeWeekdays.isEmpty else { return nil }
        let base = e.cal.dateComponents([.year, .month, .day], from: t)
        var candidates = [t]
        for off in 0...8 {
            var c = base
            c.day = base.day! + off
            c.hour = p.activeFrom / 60
            c.minute = p.activeFrom % 60
            c.second = 0
            candidates.append(e.cal.date(from: c)!)
        }
        return candidates.filter { $0 >= t && active($0) }.min()
    }
}

func randomPrefs(_ g: inout SplitMix, emptyDaysChance: Double = 0.03, allowed: [Range<Int>] = [0..<60, 240..<1440]) -> Prefs {
    func minute() -> Int {
        let r = allowed.randomElement(using: &g)!
        return Int.random(in: ((r.lowerBound + 14) / 15)...((r.upperBound - 1) / 15), using: &g) * 15
    }
    var p = Prefs()
    p.activeFrom = minute()
    p.activeUntil = Double.random(in: 0..<1, using: &g) < 0.1 ? p.activeFrom : minute()
    let roll = Double.random(in: 0..<1, using: &g)
    if roll < emptyDaysChance { p.activeWeekdays = [] }
    else if roll < 0.25 { p.activeWeekdays = [Int.random(in: 1...7, using: &g)] }
    else if roll < 0.5 { p.activeWeekdays = Set(1...7) }
    else { p.activeWeekdays = Set((1...7).filter { _ in Bool.random(using: &g) }) }
    return p
}

@Suite("Lock and on-cue window")
struct LockTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func prefs(_ style: ReminderStyle, lock: Int) -> Prefs {
        var p = Prefs()
        p.style = style
        p.lockSeconds = lock
        return p
    }

    @Test(arguments: [
        (ReminderStyle.fullscreen, 60, 60), (.fullscreen, 0, 0), (.fullscreen, 300, 300),
        (.fullscreen, -5, 0), (.fullscreen, 601, 600), (.fullscreen, Int.max, 600), (.fullscreen, Int.min, 0),
        (.banner, 60, 0), (.banner, 600, 0), (.banner, Int.max, 0),
    ])
    func effectiveLock(style: ReminderStyle, lock: Int, expected: Int) {
        #expect(prefs(style, lock: lock).effectiveLockSeconds == expected)
    }

    @Test func defaultFullscreenLockIsOneMinute() {
        #expect(Prefs().effectiveLockSeconds == 60)
    }

    @Test func onCueWindowStartsAfterTheLock() {
        #expect(prefs(.fullscreen, lock: 60).onCueDeadline(shownAt: t0) == t0 + 60 + Rules.onCueWindow)
        #expect(prefs(.fullscreen, lock: 300).onCueDeadline(shownAt: t0) == t0 + 300 + Rules.onCueWindow)
        #expect(prefs(.fullscreen, lock: 0).onCueDeadline(shownAt: t0) == t0 + Rules.onCueWindow)
    }

    @Test func bannerOnCueWindowIgnoresTheLock() {
        #expect(prefs(.banner, lock: 300).onCueDeadline(shownAt: t0) == t0 + Rules.onCueWindow)
    }

    @Test func corruptLockCannotStretchTheWindow() {
        #expect(prefs(.fullscreen, lock: Int.max).onCueDeadline(shownAt: t0) == t0 + 600 + Rules.onCueWindow)
        #expect(prefs(.fullscreen, lock: Int.min).onCueDeadline(shownAt: t0) == t0 + Rules.onCueWindow)
    }
}

@Suite("Hold during calls")
struct CallHoldTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func defaultIsOn() { #expect(Prefs().holdDuringCalls) }

    @Test func holdsWhileBusy() {
        #expect(Prefs().holdsForCall(busy: true, lastBusy: now, now: now))
        #expect(Prefs().holdsForCall(busy: true, lastBusy: nil, now: now))
    }

    @Test func freeWithNoCallSeen() {
        #expect(!Prefs().holdsForCall(busy: false, lastBusy: nil, now: now))
    }

    @Test func waitsAMinuteAfterTheCall() {
        let p = Prefs()
        #expect(p.holdsForCall(busy: false, lastBusy: now - 10, now: now))
        #expect(p.holdsForCall(busy: false, lastBusy: now - Rules.callGrace + 1, now: now))
        #expect(!p.holdsForCall(busy: false, lastBusy: now - Rules.callGrace, now: now))
        #expect(!p.holdsForCall(busy: false, lastBusy: now - 3600, now: now))
    }

    @Test func switchedOffNeverHolds() {
        var p = Prefs()
        p.holdDuringCalls = false
        #expect(!p.holdsForCall(busy: true, lastBusy: now, now: now))
        #expect(!p.holdsForCall(busy: false, lastBusy: now - 5, now: now))
    }

    @Test func settingSurvivesSavingAndOldFilesDefaultOn() throws {
        var p = Prefs()
        p.holdDuringCalls = false
        #expect(try !JSONDecoder().decode(Prefs.self, from: JSONEncoder().encode(p)).holdDuringCalls)
        #expect(try JSONDecoder().decode(Prefs.self, from: Data("{}".utf8)).holdDuringCalls)
    }
}
