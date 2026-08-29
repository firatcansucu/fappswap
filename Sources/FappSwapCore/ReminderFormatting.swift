import Foundation

/// The strings the menu rows, the input preview and the card show (spec decisions
/// 13, 14, 31). Calendar and locale are parameters so the tests are deterministic;
/// the app passes the defaults, which is how the 12/24-hour setting is honoured.
public enum ReminderFormatting {
    /// `3:42 PM` today; `Tomorrow 9:00 AM`; `Yesterday 4:00 PM`; a weekday within six
    /// days either way, `Mon 9:00 AM`; otherwise the date, `Sep 8 9:00 AM`.
    public static func dayTime(_ date: Date, now: Date, calendar: Calendar = .current,
                               locale: Locale = .current) -> String {
        let time = formatter(locale: locale, timeZone: calendar.timeZone) { $0.timeStyle = .short }
            .string(from: date)
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0:
            return time
        case 1:
            return "Tomorrow \(time)"
        case -1:
            return "Yesterday \(time)"
        case 2...6, -6...(-2):
            let weekday = formatter(locale: locale, timeZone: calendar.timeZone) {
                $0.setLocalizedDateFormatFromTemplate("EEE")
            }
            return "\(weekday.string(from: date)) \(time)"
        default:
            let day = formatter(locale: locale, timeZone: calendar.timeZone) {
                $0.setLocalizedDateFormatFromTemplate("d MMM")
            }
            return "\(day.string(from: date)) \(time)"
        }
    }

    /// `in 25 minutes`, `2 hours ago`.
    public static func relative(_ date: Date, now: Date, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// The pending row and the input preview: `3:42 PM (in 25 minutes)`.
    public static func dueLabel(_ dueDate: Date, now: Date, calendar: Calendar = .current,
                                locale: Locale = .current) -> String {
        "\(dayTime(dueDate, now: now, calendar: calendar, locale: locale)) (\(relative(dueDate, now: now, locale: locale)))"
    }

    /// The card's second line for a late reminder — one that came due while the Mac
    /// slept or the app wasn't running: `Was due 2 hours ago`. nil under a minute
    /// late, which is on time as far as anyone can tell.
    public static func overdueLabel(_ dueDate: Date, now: Date, locale: Locale = .current) -> String? {
        guard now.timeIntervalSince(dueDate) >= 60 else { return nil }
        return "Was due \(relative(dueDate, now: now, locale: locale))"
    }

    /// The log row: `Dismissed 2:10 PM`, `Cancelled Yesterday 4:00 PM`.
    public static func logLabel(_ reminder: Reminder, now: Date, calendar: Calendar = .current,
                                locale: Locale = .current) -> String {
        let verb = reminder.status == .cancelled ? "Cancelled" : "Dismissed"
        guard let finishedAt = reminder.finishedAt else { return verb }
        return "\(verb) \(dayTime(finishedAt, now: now, calendar: calendar, locale: locale))"
    }

    private static func formatter(locale: Locale, timeZone: TimeZone,
                                  configure: (DateFormatter) -> Void) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        configure(formatter)
        return formatter
    }
}
