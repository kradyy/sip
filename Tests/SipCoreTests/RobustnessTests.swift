import Testing
import Foundation
@testable import SipCore

/// A crash here would brick the app at launch: a hand-edited or corrupted prefs file decodes fine,
/// so the scheduling math itself must never trap.
@Suite("Robustness · absurd integers must not trap")
struct RobustnessTests {
    @Test func hugeIntervalFromDecodedPrefsDoesNotCrash() async {
        await #expect(processExitsWith: .success) {
            let p = try! JSONDecoder().decode(Prefs.self, from: Data(#"{"intervalMinutes": 9223372036854775807}"#.utf8))
            let e = Env()
            _ = p.nextReminder(ReminderState(anchor: e.d("2026-06-01 10:00")), now: e.d("2026-06-01 10:00"), calendar: e.cal)
        }
    }

    @Test func hugeSnoozeMinutesDoesNotCrash() async {
        await #expect(processExitsWith: .success) {
            var s = ReminderState(anchor: Date())
            s.snooze(at: Date(), minutes: Int.max)
        }
    }

    @Test func largeButPlausibleValuesAreFine() {
        let e = Env()
        var p = P()
        p.intervalMinutes = 10_000_000          // ~19 years
        let s = ReminderState(anchor: e.d("2026-06-01 10:00"))
        #expect(p.nextReminder(s, now: e.d("2026-06-01 10:00"), calendar: e.cal) != nil)
    }
}

@Suite("Robustness · absurd ledger values")
struct AbsurdLedgerTests {
    @Test func hugeGoalAndDrinkDoNotTrap() {
        let e = Env()
        var p = P()
        p.dailyGoalML = Int.max
        let now = e.d("2026-06-01 12:00")
        let l = Ledger(startedAt: e.d("2026-05-30 09:00"), drinks: [Drink(at: e.d("2026-06-01 10:00"), ml: Int.max)],
                       goals: ["2026-05-30": Int.max])
        let s = Progression.compute(ledger: l, prefs: p, now: now, calendar: e.cal)
        #expect(s.todayML == Rules.maxDrinkML)
        #expect(s.todayGoal == Rules.maxGoalML)
    }

    @Test func goalTrophyIsStampedWithTheCrossingDrink() {
        let e = Env()
        let crossing = e.d("2026-06-01 11:00")
        let l = Ledger(startedAt: e.d("2026-06-01 09:00"), drinks: [
            Drink(at: e.d("2026-06-01 10:00"), ml: 1500),
            Drink(at: crossing, ml: 1000),
            Drink(at: e.d("2026-06-01 15:00"), ml: 1500),
        ])
        let s = Progression.compute(ledger: l, prefs: P(goal: 2500), now: e.d("2026-06-01 20:00"), calendar: e.cal)
        #expect(s.unlocked[.goalGetter] == crossing)
        #expect(s.unlocked[.overflow] == e.d("2026-06-01 15:00"))
    }
}

@Suite("Robustness · ledger decoding")
struct LedgerDecodingTests {
    @Test func oneBadDrinkDoesNotCostTheHistory() throws {
        let json = #"""
        {"startedAt": 770000000, "goals": {},
         "drinks": [{"at": 770000100, "ml": 250}, {"at": 770000200}, {"ml": 300}, {"at": 770000300, "ml": 330, "onCue": true}]}
        """#
        let l = try JSONDecoder().decode(Ledger.self, from: Data(json.utf8))
        #expect(l.drinks.map(\.ml) == [250, 330])
        #expect(l.drinks.last?.onCue == true)
    }

    @Test func missingStartAndGoalsAreRebuilt() throws {
        let l = try JSONDecoder().decode(Ledger.self, from: Data(#"{"drinks": [{"at": 770000500, "ml": 200}, {"at": 770000100, "ml": 100}]}"#.utf8))
        #expect(l.startedAt == Date(timeIntervalSinceReferenceDate: 770000100))
        #expect(l.goals.isEmpty)
    }
}
