import Foundation
@testable import SipCore

/// A gregorian calendar pinned to one time zone. Every test builds dates through this, never the machine's zone.
struct Env: Sendable {
    let cal: Calendar
    init(_ tz: String = "Europe/Stockholm") {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz)!
        cal = c
    }

    /// "2026-06-01", "2026-06-01 08:00" or "2026-06-01 08:00:30", read as local time. Ambiguous times resolve to the first pass.
    func d(_ s: String) -> Date {
        let parts = s.split(separator: " ")
        let ymd = parts[0].split(separator: "-").map { Int($0)! }
        let hms = parts.count > 1 ? parts[1].split(separator: ":").map { Int($0)! } : []
        let c = DateComponents(year: ymd[0], month: ymd[1], day: ymd[2],
                               hour: hms.count > 0 ? hms[0] : 0,
                               minute: hms.count > 1 ? hms[1] : 0,
                               second: hms.count > 2 ? hms[2] : 0)
        return cal.date(from: c)!
    }

    /// Inverse of `d`, always with seconds so failure diffs are unambiguous. "nil" for nil.
    func s(_ date: Date?) -> String {
        guard let date else { return "nil" }
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04ld-%02ld-%02ld %02ld:%02ld:%02ld",
                      c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }

    func offsetHours(_ date: Date) -> Int { cal.timeZone.secondsFromGMT(for: date) / 3600 }
}

func hm(_ h: Int, _ m: Int = 0) -> Int { h * 60 + m }

/// Prefs builder. Weekdays: 1 = Sun, 2 = Mon … 7 = Sat.
func P(_ from: Int = hm(8), _ until: Int = hm(22), days: Set<Int> = Set(1...7), interval: Int = 45, goal: Int = 2500) -> Prefs {
    var p = Prefs()
    p.activeFrom = from
    p.activeUntil = until
    p.activeWeekdays = days
    p.intervalMinutes = interval
    p.dailyGoalML = goal
    return p
}

/// Civil-date arithmetic in UTC: independent of any DST behaviour in the calendar under test.
func civil(_ day: String, plus n: Int) -> String {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let p = day.split(separator: "-").map { Int($0)! }
    let base = utc.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
    let c = utc.dateComponents([.year, .month, .day], from: utc.date(byAdding: .day, value: n, to: base)!)
    return String(format: "%04ld-%02ld-%02ld", c.year!, c.month!, c.day!)
}

func civilWeekday(_ day: String) -> Int {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let p = day.split(separator: "-").map { Int($0)! }
    return utc.component(.weekday, from: utc.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!)
}

/// Deterministic generator so every failure is reproducible from its seed.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A DST-observing zone with its two 2026 transition days (and the days around them).
struct Zone: Sendable, CustomStringConvertible {
    let id: String
    let springEve, spring, springNext: String
    let fallEve, fall, fallNext: String
    var description: String { id }

    static let all = [
        Zone(id: "Europe/Stockholm", springEve: "2026-03-28", spring: "2026-03-29", springNext: "2026-03-30",
             fallEve: "2026-10-24", fall: "2026-10-25", fallNext: "2026-10-26"),
        Zone(id: "America/New_York", springEve: "2026-03-07", spring: "2026-03-08", springNext: "2026-03-09",
             fallEve: "2026-10-31", fall: "2026-11-01", fallNext: "2026-11-02"),
    ]

    /// Zones whose DST jump happens at local midnight: the transition day has no 00:xx (spring) or a repeated 23:xx (fall).
    /// Chile and Egypt observe this today; São Paulo did until 2019.
    static let midnight = [
        Zone(id: "America/Santiago", springEve: "2026-09-05", spring: "2026-09-06", springNext: "2026-09-07",
             fallEve: "2026-04-03", fall: "2026-04-04", fallNext: "2026-04-05"),
        Zone(id: "Africa/Cairo", springEve: "2026-04-23", spring: "2026-04-24", springNext: "2026-04-25",
             fallEve: "2026-10-28", fall: "2026-10-29", fallNext: "2026-10-30"),
        Zone(id: "America/Sao_Paulo", springEve: "2018-11-03", spring: "2018-11-04", springNext: "2018-11-05",
             fallEve: "2018-02-16", fall: "2018-02-17", fallNext: "2018-02-18"),
    ]

    static let every = all + midnight
}
