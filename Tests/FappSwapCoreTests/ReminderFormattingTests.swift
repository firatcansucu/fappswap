import Foundation
import Testing
@testable import FappSwapCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()
private let enUS = Locale(identifier: "en_US")

/// Saturday 2026-08-29 10:00:00 UTC.
private let now = Date(timeIntervalSince1970: 1_787_997_600)

private extension String {
    /// Recent macOS puts a narrow no-break space (U+202F) before AM/PM. The
    /// tests care about the words, not the width of the space.
    var plainSpaces: String { replacingOccurrences(of: "\u{202F}", with: " ") }
}

private func dayTime(_ date: Date) -> String {
    ReminderFormatting.dayTime(date, now: now, calendar: utc, locale: enUS).plainSpaces
}

@Test func dayTimeToday() {
    #expect(dayTime(now + 2 * 3_600) == "12:00 PM")
    #expect(dayTime(now - 30 * 60) == "9:30 AM")
}

@Test func dayTimeTomorrowAndYesterday() {
    #expect(dayTime(now + 23 * 3_600) == "Tomorrow 9:00 AM")
    #expect(dayTime(now - 18 * 3_600) == "Yesterday 4:00 PM")
}

@Test func dayTimeWithinTheWeekUsesTheWeekday() {
    #expect(dayTime(now + 2 * 86_400) == "Mon 10:00 AM")
    #expect(dayTime(now + 6 * 86_400) == "Fri 10:00 AM")
    #expect(dayTime(now - 3 * 86_400) == "Wed 10:00 AM")
}

@Test func dayTimeFurtherAwayUsesTheDate() {
    #expect(dayTime(now + 7 * 86_400) == "Sep 5 10:00 AM")
    #expect(dayTime(now + 10 * 86_400) == "Sep 8 10:00 AM")
}

@Test func relativeIsWordy() {
    #expect(ReminderFormatting.relative(now + 25 * 60, now: now, locale: enUS) == "in 25 minutes")
    #expect(ReminderFormatting.relative(now - 2 * 3_600, now: now, locale: enUS) == "2 hours ago")
}

@Test func dueLabelCombinesBoth() {
    #expect(ReminderFormatting.dueLabel(now + 2 * 3_600, now: now, calendar: utc, locale: enUS).plainSpaces
        == "12:00 PM (in 2 hours)")
}

@Test func overdueLabelOnlyWhenAtLeastAMinuteLate() {
    #expect(ReminderFormatting.overdueLabel(now - 2 * 3_600, now: now, locale: enUS) == "Was due 2 hours ago")
    #expect(ReminderFormatting.overdueLabel(now - 60, now: now, locale: enUS) == "Was due 1 minute ago")
    #expect(ReminderFormatting.overdueLabel(now - 30, now: now, locale: enUS) == nil)
    #expect(ReminderFormatting.overdueLabel(now + 30, now: now, locale: enUS) == nil)
}

@Test func logLabelNamesTheVerbAndTheTime() {
    let dismissed = Reminder(text: "x", createdAt: now, dueDate: now, status: .dismissed, finishedAt: now - 30 * 60)
    let cancelled = Reminder(text: "x", createdAt: now, dueDate: now, status: .cancelled, finishedAt: now - 18 * 3_600)
    #expect(ReminderFormatting.logLabel(dismissed, now: now, calendar: utc, locale: enUS).plainSpaces == "Dismissed 9:30 AM")
    #expect(ReminderFormatting.logLabel(cancelled, now: now, calendar: utc, locale: enUS).plainSpaces == "Cancelled Yesterday 4:00 PM")
}
