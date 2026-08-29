import Foundation
import Testing
@testable import FappSwapCore

private func makeTempURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fappswap-test-\(UUID().uuidString)")
        .appendingPathComponent("reminders.json")
}

/// 2026-08-29 10:00:00 UTC.
private let now = Date(timeIntervalSince1970: 1_787_997_600)
private func minutes(_ m: Double) -> TimeInterval { m * 60 }

@Test func reminderStoreStartsEmpty() {
    let store = ReminderStore(url: makeTempURL())
    #expect(store.reminders.isEmpty)
    #expect(store.pending.isEmpty)
    #expect(store.nextDueDate == nil)
    #expect(!store.didRecoverFromCorruptFile)
}

@Test func addSavesImmediatelyAndReloads() throws {
    let url = makeTempURL()
    let store = ReminderStore(url: url)
    let added = try store.add(text: "tea time", dueDate: now + minutes(30), now: now)
    #expect(added.status == .pending)
    #expect(added.createdAt == now)

    let reloaded = ReminderStore(url: url)
    #expect(reloaded.reminders.count == 1)
    #expect(reloaded.reminders[0].id == added.id)
    #expect(reloaded.reminders[0].text == "tea time")
    #expect(reloaded.reminders[0].dueDate == now + minutes(30))
}

@Test func reminderStoreWritesTheDocumentedFileShape() throws {
    let url = makeTempURL()
    let store = ReminderStore(url: url)
    try store.add(text: "tea time", dueDate: now + minutes(30), now: now)

    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    #expect(json?["version"] as? Int == 1)
    let reminders = json?["reminders"] as? [[String: Any]]
    #expect(reminders?.count == 1)
    #expect(reminders?[0]["text"] as? String == "tea time")
    #expect(reminders?[0]["status"] as? String == "pending")
    #expect(reminders?[0]["snoozeCount"] as? Int == 0)
}

@Test func pendingIsSortedEarliestFirstAndNextDueIsTheEarliest() throws {
    let store = ReminderStore(url: makeTempURL())
    try store.add(text: "later", dueDate: now + minutes(60), now: now)
    try store.add(text: "sooner", dueDate: now + minutes(5), now: now)
    #expect(store.pending.map(\.text) == ["sooner", "later"])
    #expect(store.nextDueDate == now + minutes(5))
}

@Test func fireDueMovesOnlyWhatHasComeDue() throws {
    let store = ReminderStore(url: makeTempURL())
    try store.add(text: "later", dueDate: now + minutes(60), now: now)
    let early = try store.add(text: "early", dueDate: now - minutes(10), now: now - minutes(20))
    let onTime = try store.add(text: "on time", dueDate: now, now: now - minutes(5))

    let fired = try store.fireDue(now: now)
    #expect(fired.map(\.id) == [early.id, onTime.id])   // earliest first
    #expect(fired.allSatisfy { $0.status == .due && $0.shownAt == now })
    #expect(store.due.count == 2)
    #expect(store.pending.map(\.text) == ["later"])
    #expect(store.nextDueDate == now + minutes(60))
}

@Test func fireDueWithNothingDueReturnsEmptyAndDoesNotWrite() throws {
    let url = makeTempURL()
    let store = ReminderStore(url: url)
    #expect(try store.fireDue(now: now).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test func dismissMovesADueReminderToTheLog() throws {
    let store = ReminderStore(url: makeTempURL())
    let r = try store.add(text: "x", dueDate: now, now: now)
    _ = try store.fireDue(now: now)
    try store.dismiss(ids: [r.id], now: now + minutes(1))
    #expect(store.due.isEmpty)
    #expect(store.log.count == 1)
    #expect(store.log[0].status == .dismissed)
    #expect(store.log[0].finishedAt == now + minutes(1))
}

@Test func dismissIgnoresReminderThatIsNotDue() throws {
    let store = ReminderStore(url: makeTempURL())
    let r = try store.add(text: "x", dueDate: now + minutes(30), now: now)
    try store.dismiss(ids: [r.id], now: now)
    #expect(store.pending.count == 1)
    #expect(store.log.isEmpty)
}

@Test func snoozeReturnsADueReminderToPendingWithANewTime() throws {
    let store = ReminderStore(url: makeTempURL())
    let r = try store.add(text: "x", dueDate: now, now: now)
    _ = try store.fireDue(now: now)
    try store.snooze(ids: [r.id], minutes: 15, now: now + minutes(2))
    let snoozed = store.pending[0]
    #expect(snoozed.id == r.id)
    #expect(snoozed.status == .pending)
    #expect(snoozed.dueDate == now + minutes(17))
    #expect(snoozed.snoozeCount == 1)
    #expect(snoozed.shownAt == now)   // kept from the first showing
    #expect(store.nextDueDate == now + minutes(17))
}

@Test func cancelOnlyTouchesAPendingReminder() throws {
    let store = ReminderStore(url: makeTempURL())
    let pending = try store.add(text: "p", dueDate: now + minutes(30), now: now)
    let due = try store.add(text: "d", dueDate: now, now: now)
    _ = try store.fireDue(now: now)

    try store.cancel(id: pending.id, now: now)
    try store.cancel(id: due.id, now: now)
    #expect(store.pending.isEmpty)
    #expect(store.due.map(\.id) == [due.id])
    #expect(store.log.map(\.id) == [pending.id])
    #expect(store.log[0].status == .cancelled)
    #expect(store.log[0].finishedAt == now)
}

@Test func logIsNewestFinishedFirst() throws {
    let store = ReminderStore(url: makeTempURL())
    let a = try store.add(text: "a", dueDate: now + minutes(1), now: now)
    let b = try store.add(text: "b", dueDate: now + minutes(2), now: now)
    try store.cancel(id: a.id, now: now + minutes(1))
    try store.cancel(id: b.id, now: now + minutes(5))
    #expect(store.log.map(\.text) == ["b", "a"])
}

@Test func pruneLogRemovesOnlyFinishedRemindersOlderThanRetention() throws {
    let store = ReminderStore(url: makeTempURL())
    let old = try store.add(text: "old", dueDate: now, now: now)
    let recent = try store.add(text: "recent", dueDate: now, now: now)
    try store.add(text: "pending", dueDate: now + minutes(30), now: now)
    try store.cancel(id: old.id, now: now - ReminderStore.logRetention - 1)
    try store.cancel(id: recent.id, now: now - minutes(1))

    #expect(try store.pruneLog(now: now) == 1)
    #expect(store.log.map(\.text) == ["recent"])
    #expect(store.pending.map(\.text) == ["pending"])
    #expect(try store.pruneLog(now: now) == 0)
}

@Test func clearLogKeepsPendingAndDue() throws {
    let store = ReminderStore(url: makeTempURL())
    let finished = try store.add(text: "f", dueDate: now, now: now)
    try store.add(text: "p", dueDate: now + minutes(30), now: now)
    try store.add(text: "d", dueDate: now, now: now)
    try store.cancel(id: finished.id, now: now)
    _ = try store.fireDue(now: now)

    #expect(try store.clearLog() == 1)
    #expect(store.log.isEmpty)
    #expect(store.pending.count == 1)
    #expect(store.due.count == 1)
}

@Test func reminderStoreBacksUpAndRecoversFromCorruptFile() throws {
    let url = makeTempURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("this is not json".utf8).write(to: url)

    let store = ReminderStore(url: url)
    #expect(store.reminders.isEmpty)
    #expect(store.didRecoverFromCorruptFile)
    #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("bak").path))
}

@Test func storeTreatsUnknownStatusAsCorrupt() throws {
    let url = makeTempURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let bad = #"{"version":1,"reminders":[{"id":"5B8C8F1E-1C2D-4E3F-8A9B-0C1D2E3F4A5B","text":"x","createdAt":0,"dueDate":0,"status":"exploded","snoozeCount":0}]}"#
    try Data(bad.utf8).write(to: url)

    let store = ReminderStore(url: url)
    #expect(store.reminders.isEmpty)
    #expect(store.didRecoverFromCorruptFile)
}

@Test func reminderStoreWritesTheFileReadableOnlyByItsOwner() throws {
    let url = makeTempURL()
    let store = ReminderStore(url: url)
    try store.add(text: "x", dueDate: now + minutes(1), now: now)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect(attributes[.posixPermissions] as? Int == 0o600)
}
