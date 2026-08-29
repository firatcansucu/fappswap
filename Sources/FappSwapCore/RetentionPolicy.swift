/// The five choices the **Keep History For** submenu offers. Raw value is the day
/// count, which is also what `UserDefaults` stores.
public enum RetentionDays: Int, CaseIterable, Codable, Sendable {
    case one = 1
    case seven = 7
    case thirty = 30
    case ninety = 90
    case year = 365

    public var label: String {
        switch self {
        case .one: return "1 day"
        case .seven: return "7 days"
        case .thirty: return "30 days"
        case .ninety: return "90 days"
        case .year: return "1 year"
        }
    }
}

/// What `ClipboardHistoryStore.prune` enforces. The caps are instance values
/// with the documented defaults so tests can use small ones; the app never
/// changes them.
public struct RetentionPolicy: Equatable, Sendable {
    public var days: RetentionDays
    public var maxItems: Int
    public var maxImageBytes: Int

    /// A single text item larger than this (UTF-8) is not recorded at all.
    public static let maxTextBytes = 1_024 * 1_024

    /// A single image larger than this (raw pasteboard bytes, before decode)
    /// is not recorded at all. This is a per-item bound, checked before any
    /// decoding happens; it is separate from `maxImageBytes`, the aggregate
    /// cap `prune` enforces across the whole history.
    public static let maxSingleImageBytes = 100 * 1_024 * 1_024

    public init(days: RetentionDays, maxItems: Int = 1_000, maxImageBytes: Int = 250 * 1_024 * 1_024) {
        self.days = days
        self.maxItems = maxItems
        self.maxImageBytes = maxImageBytes
    }
}
