import Foundation

/// Time zones chosen to break different assumptions. `Australia/Lord_Howe` is the
/// important one: its DST shift is **30 minutes**, so any code that quietly assumes
/// "±1 hour" fails there loudly instead of silently.
enum Zone {
    static let newYork = "America/New_York"      // US spring-forward / fall-back
    static let phoenix = "America/Phoenix"       // no DST — control
    static let lordHowe = "Australia/Lord_Howe"  // 30-minute DST shift
    static let london = "Europe/London"          // transition at 01:00, not 02:00
}

/// Builds a Date from a wall-clock string in a named zone.
/// Format: "yyyy-MM-dd HH:mm".
func makeDate(_ wallClock: String, _ zoneID: String) -> Date {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: zoneID)
    f.dateFormat = "yyyy-MM-dd HH:mm"
    guard let d = f.date(from: wallClock) else {
        fatalError("test fixture: could not parse \(wallClock) in \(zoneID)")
    }
    return d
}

func calendar(_ zoneID: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: zoneID)!
    return c
}
