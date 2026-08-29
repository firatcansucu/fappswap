import Foundation
import Testing
@testable import FappSwapCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}()

/// Saturday 2026-08-29 10:00:00 UTC.
private let now = Date(timeIntervalSince1970: 1_787_997_600)

private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 8) -> Date {
    utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private func parse(_ text: String, now: Date = now) -> Result<Date, ReminderTimeParser.Failure> {
    ReminderTimeParser.parse(text, now: now, calendar: utc)
}

// MARK: - Durations

@Test func durations() {
    #expect(parse("30m") == .success(now + 1_800))
    #expect(parse("1h") == .success(now + 3_600))
    #expect(parse("1h30m") == .success(now + 5_400))
    #expect(parse("1h 30m") == .success(now + 5_400))
    #expect(parse("2d") == .success(now + 172_800))
    #expect(parse("in 45 min") == .success(now + 2_700))
    #expect(parse("2 hours") == .success(now + 7_200))
    #expect(parse("  1H  ") == .success(now + 3_600))
}

@Test func durationLimits() {
    #expect(parse("0m") == .failure(.tooSoon))
    #expect(parse("1m") == .success(now + 60))
    #expect(parse("365d") == .success(now + 365 * 86_400))
    #expect(parse("366d") == .failure(.tooFar))
}

// MARK: - Clock times (decision 5: an ambiguous hour is the next one that hasn't passed)

@Test func explicitClockTimesToday() {
    #expect(parse("15:30") == .success(at(29, 15, 30)))
    #expect(parse("3pm") == .success(at(29, 15)))
    #expect(parse("3:30 pm") == .success(at(29, 15, 30)))
    #expect(parse("at 3pm") == .success(at(29, 15)))
    #expect(parse("11am") == .success(at(29, 11)))
    #expect(parse("15") == .success(at(29, 15)))
    #expect(parse("0:30") == .success(at(30, 0, 30)))   // midnight has passed today
}

@Test func ambiguousHourIsTheNextOccurrence() {
    #expect(parse("5") == .success(at(29, 17)))            // 5 AM passed → 5 PM
    #expect(parse("9:00") == .success(at(29, 21)))         // 9 AM passed → 9 PM
    #expect(parse("11") == .success(at(29, 11)))           // 11 AM still ahead
    #expect(parse("5", now: at(29, 18)) == .success(at(30, 5)))   // both passed → tomorrow 5 AM
    #expect(parse("12") == .success(at(29, 12)))           // noon, never midnight
}

@Test func passedExplicitTimeRollsToTomorrow() {
    #expect(parse("9am") == .success(at(30, 9)))
    #expect(parse("9:59") == .success(at(29, 21, 59)))
    #expect(parse("10:00") == .success(at(29, 22)))        // exactly now is not "ahead"
    #expect(parse("10:01") == .success(at(29, 10, 1)))
}

// MARK: - Day words (decision 8: a day word alone means 9:00, tonight means 20:00)

@Test func dayWords() {
    #expect(parse("tomorrow") == .success(at(30, 9)))
    #expect(parse("tomorrow 5pm") == .success(at(30, 17)))
    #expect(parse("tomorrow at 17:00") == .success(at(30, 17)))
    #expect(parse("tonight") == .success(at(29, 20)))
    #expect(parse("tonight", now: at(29, 21)) == .success(at(30, 20)))
    #expect(parse("today 11am") == .success(at(29, 11)))
    #expect(parse("today 9am") == .success(at(30, 9)))     // passed → rolls
}

@Test func weekdays() {
    #expect(parse("monday") == .success(at(31, 9)))
    #expect(parse("mon 5pm") == .success(at(31, 17)))
    #expect(parse("Sunday") == .success(at(30, 9)))
    #expect(parse("saturday") == .success(at(5, 9, month: 9)))   // today's weekday → next week (decision 6)
    #expect(parse("fri") == .success(at(4, 9, month: 9)))
}

// MARK: - Refusals

@Test func unrecognisedInputs() {
    for text in ["", "   ", "banana", "12:5", "25:00", "13pm", "in", "5 bananas", "tomorrow banana", "1.5h"] {
        #expect(parse(text) == .failure(.unrecognized), "\(text)")
    }
}

@Test func failureMessagesAreTheSpecWording() {
    #expect(ReminderTimeParser.Failure.unrecognized.message
        == "I don't understand that time. Try 30m, 1h30m, 15:30, 3pm, tomorrow 9am or monday.")
    #expect(ReminderTimeParser.Failure.tooSoon.message == "At least one minute from now.")
    #expect(ReminderTimeParser.Failure.tooFar.message == "At most one year from now.")
}
