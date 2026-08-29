import Foundation

/// Turns the second step of the reminder dialog — "when?" — into a due date.
/// The grammar is deliberately small (spec decision 8): a duration, a clock
/// time, or a day word optionally followed by a clock time. Anything else is
/// `unrecognized`; the dialog shows the message and shakes.
public enum ReminderTimeParser {
    public enum Failure: Error, Equatable, Sendable {
        case unrecognized
        case tooSoon
        case tooFar

        public var message: String {
            switch self {
            case .unrecognized:
                return "I don't understand that time. Try 30m, 1h30m, 15:30, 3pm, tomorrow 9am or monday."
            case .tooSoon: return "At least one minute from now."
            case .tooFar: return "At most one year from now."
            }
        }
    }

    /// Decision 7: under a minute is a typo, over a year is a typo.
    public static let minimumLead: TimeInterval = 60
    public static let maximumLead: TimeInterval = 365 * 86_400
    /// A day word with no time (`tomorrow`, `monday`) means this hour.
    public static let defaultHour = 9
    /// `tonight` means this hour.
    public static let tonightHour = 20

    public static func parse(_ input: String, now: Date, calendar: Calendar = .current) -> Result<Date, Failure> {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return .failure(.unrecognized) }
        let candidate: Date
        if let seconds = duration(text) {
            candidate = now.addingTimeInterval(seconds)
        } else if let date = absolute(text, now: now, calendar: calendar) {
            candidate = date
        } else {
            return .failure(.unrecognized)
        }
        let lead = candidate.timeIntervalSince(now)
        if lead < minimumLead { return .failure(.tooSoon) }
        if lead > maximumLead { return .failure(.tooFar) }
        return .success(candidate)
    }

    // MARK: - Durations

    /// `30m`, `1h30m`, `2d`, `1h 30m`, `in 45 min`, `2 hours`. nil when the text
    /// isn't a duration — including a bare number, which `absolute` reads as an hour.
    static func duration(_ text: String) -> TimeInterval? {
        var rest = Substring(text)
        if rest.hasPrefix("in ") { rest = rest.dropFirst(3) }
        var total: TimeInterval = 0
        var seenAny = false
        while true {
            rest = rest.drop(while: { $0 == " " })
            if rest.isEmpty { break }
            let digits = rest.prefix(while: { $0.isNumber })
            guard let value = Double(String(digits)) else { return nil }
            rest = rest.dropFirst(digits.count).drop(while: { $0 == " " })
            let unit = rest.prefix(while: { $0.isLetter })
            rest = rest.dropFirst(unit.count)
            switch unit {
            case "m", "min", "mins", "minute", "minutes": total += value * 60
            case "h", "hr", "hrs", "hour", "hours": total += value * 3_600
            case "d", "day", "days": total += value * 86_400
            default: return nil
            }
            seenAny = true
        }
        return seenAny ? total : nil
    }

    // MARK: - Clock times and day words

    /// `Calendar.component(.weekday)` numbering: Sunday is 1.
    private static let weekdays: [String: Int] = [
        "sun": 1, "sunday": 1, "mon": 2, "monday": 2, "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "wednesday": 4, "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6, "sat": 7, "saturday": 7,
    ]

    /// `15:30`, `3pm`, `5`, and `today` / `tonight` / `tomorrow` / a weekday name,
    /// each optionally followed by a time. nil when the text is neither.
    static func absolute(_ text: String, now: Date, calendar: Calendar) -> Date? {
        var words = text.split(separator: " ").map(String.init)
        if words.first == "at" { words.removeFirst() }
        guard let first = words.first else { return nil }

        // nil means "no day word": the next occurrence of the time, today or tomorrow.
        var dayOffset: Int?
        var hourIfNoTime = defaultHour
        if first == "today" {
            dayOffset = 0
        } else if first == "tomorrow" {
            dayOffset = 1
        } else if first == "tonight" {
            dayOffset = 0
            hourIfNoTime = tonightHour
        } else if let weekday = weekdays[first] {
            let today = calendar.component(.weekday, from: now)
            let delta = (weekday - today + 7) % 7
            // Decision 6: today's own weekday means next week, not in a minute.
            dayOffset = delta == 0 ? 7 : delta
        }
        if dayOffset != nil { words.removeFirst() }
        if words.first == "at" { words.removeFirst() }

        var time: ClockTime?
        if !words.isEmpty {
            guard let parsed = clockTime(words.joined()) else { return nil }
            time = parsed
        }
        guard dayOffset != nil || time != nil else { return nil }

        let hours: [Int]
        let minute: Int
        if let time {
            // Decision 5: an ambiguous hour (`5`, `9:30`) is tried as AM, then PM.
            hours = time.explicit || time.hour >= 12 ? [time.hour] : [time.hour, time.hour + 12]
            minute = time.minute
        } else {
            hours = [hourIfNoTime]
            minute = 0
        }

        // "Hasn't passed" means at least the minimum lead away, so `10:00` typed at
        // 09:59:30 doesn't produce a reminder that is refused as too soon a moment later.
        let threshold = now.addingTimeInterval(minimumLead)
        let startOfToday = calendar.startOfDay(for: now)
        // The named day (or today) first, then the day after, so a passed time rolls
        // forward (decision 6). `tomorrow` and a weekday are already ahead, so their
        // first candidate wins.
        for offset in [dayOffset ?? 0, (dayOffset ?? 0) + 1] {
            for hour in hours {
                guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                      let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
                else { continue }
                if candidate >= threshold { return candidate }
            }
        }
        return nil
    }

    struct ClockTime: Equatable {
        /// 0–23.
        var hour: Int
        var minute: Int
        /// True when am/pm or a 24-hour value settled which half of the day it is.
        var explicit: Bool
    }

    /// `15:30`, `3pm`, `3:30pm`, `5`, `0:45`. Minutes need two digits, so `12:5` is
    /// refused rather than guessed at.
    static func clockTime(_ text: String) -> ClockTime? {
        var body = text
        var suffix: String?
        for candidate in ["am", "pm"] where body.hasSuffix(candidate) {
            suffix = candidate
            body.removeLast(2)
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let hour = Int(parts[0]) else { return nil }
        var minute = 0
        if parts.count == 2 {
            guard parts[1].count == 2, let value = Int(parts[1]), (0...59).contains(value) else { return nil }
            minute = value
        }
        switch suffix {
        case "am":
            guard (1...12).contains(hour) else { return nil }
            return ClockTime(hour: hour % 12, minute: minute, explicit: true)
        case "pm":
            guard (1...12).contains(hour) else { return nil }
            return ClockTime(hour: hour % 12 + 12, minute: minute, explicit: true)
        default:
            guard (0...23).contains(hour) else { return nil }
            return ClockTime(hour: hour, minute: minute, explicit: hour == 0 || hour > 12)
        }
    }
}
