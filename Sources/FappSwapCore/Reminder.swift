import Foundation

/// Where a reminder is in its life. `due` means it is on the card right now.
public enum ReminderStatus: String, Codable, Equatable, Sendable {
    case pending
    case due
    case dismissed
    case cancelled
}

public struct Reminder: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// Taken verbatim from the first step of the dialog; never parsed (spec decision 4).
    public let text: String
    public let createdAt: Date
    public var dueDate: Date
    public var status: ReminderStatus
    public var snoozeCount: Int
    /// When it first reached the card. Kept across snoozes.
    public var shownAt: Date?
    /// When it was dismissed or cancelled — what the log sorts and prunes by.
    public var finishedAt: Date?

    public init(id: UUID = UUID(), text: String, createdAt: Date, dueDate: Date,
                status: ReminderStatus = .pending, snoozeCount: Int = 0,
                shownAt: Date? = nil, finishedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.status = status
        self.snoozeCount = snoozeCount
        self.shownAt = shownAt
        self.finishedAt = finishedAt
    }

    public var isFinished: Bool { status == .dismissed || status == .cancelled }
}
