import Foundation

struct ReminderFile: Codable {
    var version: Int
    var reminders: [Reminder]
}

/// Not thread-safe; main thread only. Every mutator saves before returning, as
/// `ClipboardHistoryStore` does, so the file never lags what the menu and the
/// card show. A mutator that changes nothing writes nothing.
public final class ReminderStore {
    public private(set) var reminders: [Reminder] = []
    /// True when the last load found an unreadable file and started over.
    public private(set) var didRecoverFromCorruptFile = false

    /// Finished reminders older than this are dropped by `pruneLog` (spec decision 29).
    public static let logRetention: TimeInterval = 30 * 86_400

    private let url: URL

    public init(url: URL) {
        self.url = url
        load()
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("fappswap", isDirectory: true)
            .appendingPathComponent("reminders.json")
    }

    public func load() {
        didRecoverFromCorruptFile = false
        guard FileManager.default.fileExists(atPath: url.path) else {
            reminders = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            reminders = try JSONDecoder().decode(ReminderFile.self, from: data).reminders
        } catch {
            // Mirrors `BindingStore`: back the file up rather than silently
            // discarding it, so a later save() doesn't clobber real data.
            let backup = url.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            reminders = []
            didRecoverFromCorruptFile = true
        }
    }

    public func save() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(ReminderFile(version: 1, reminders: reminders))
        try data.write(to: url, options: .atomic)
        // Owner-only, like the other stores: reminder text is user content.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: - Views

    /// Waiting for their time, earliest first.
    public var pending: [Reminder] {
        reminders.filter { $0.status == .pending }.sorted { $0.dueDate < $1.dueDate }
    }

    /// On the card right now, earliest first.
    public var due: [Reminder] {
        reminders.filter { $0.status == .due }.sorted { $0.dueDate < $1.dueDate }
    }

    /// Dismissed and cancelled, most recently finished first.
    public var log: [Reminder] {
        reminders.filter(\.isFinished)
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }

    public var nextDueDate: Date? { pending.first?.dueDate }

    // MARK: - Transitions

    @discardableResult
    public func add(text: String, dueDate: Date, now: Date) throws -> Reminder {
        let reminder = Reminder(text: text, createdAt: now, dueDate: dueDate)
        reminders.append(reminder)
        try save()
        return reminder
    }

    /// Every pending reminder whose time has come becomes `due`. Returned earliest
    /// first; empty when nothing changed, in which case nothing is written.
    public func fireDue(now: Date) throws -> [Reminder] {
        var fired: [Reminder] = []
        for index in reminders.indices
        where reminders[index].status == .pending && reminders[index].dueDate <= now {
            reminders[index].status = .due
            if reminders[index].shownAt == nil { reminders[index].shownAt = now }
            fired.append(reminders[index])
        }
        guard !fired.isEmpty else { return [] }
        try save()
        return fired.sorted { $0.dueDate < $1.dueDate }
    }

    public func dismiss(ids: Set<UUID>, now: Date) throws {
        try transition(ids: ids, from: .due) {
            $0.status = .dismissed
            $0.finishedAt = now
        }
    }

    /// Back to pending, `minutes` from now. `shownAt` is kept — it records the
    /// first showing, and a snoozed reminder has already been seen once.
    public func snooze(ids: Set<UUID>, minutes: Int, now: Date) throws {
        try transition(ids: ids, from: .due) {
            $0.status = .pending
            $0.dueDate = now.addingTimeInterval(TimeInterval(minutes) * 60)
            $0.snoozeCount += 1
        }
    }

    /// Only a pending reminder can be cancelled; one on the card is dismissed instead.
    public func cancel(id: UUID, now: Date) throws {
        try transition(ids: [id], from: .pending) {
            $0.status = .cancelled
            $0.finishedAt = now
        }
    }

    /// Drops finished reminders older than `logRetention`. Returns how many.
    @discardableResult
    public func pruneLog(now: Date) throws -> Int {
        let cutoff = now.addingTimeInterval(-Self.logRetention)
        let before = reminders.count
        reminders.removeAll { $0.isFinished && ($0.finishedAt ?? .distantPast) < cutoff }
        let removed = before - reminders.count
        if removed > 0 { try save() }
        return removed
    }

    /// Drops every finished reminder. Pending and due ones stay. Returns how many.
    @discardableResult
    public func clearLog() throws -> Int {
        let before = reminders.count
        reminders.removeAll(where: \.isFinished)
        let removed = before - reminders.count
        if removed > 0 { try save() }
        return removed
    }

    private func transition(ids: Set<UUID>, from status: ReminderStatus,
                            _ change: (inout Reminder) -> Void) throws {
        var changed = false
        for index in reminders.indices
        where ids.contains(reminders[index].id) && reminders[index].status == status {
            change(&reminders[index])
            changed = true
        }
        if changed { try save() }
    }
}
