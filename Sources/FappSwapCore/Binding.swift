import Foundation

public struct Binding: Codable, Equatable, Identifiable, Sendable {
    /// Hardware virtual key code — layout independent.
    public let keyCode: UInt16
    public let modifiers: Set<Modifier>
    /// Stable app identifier; survives renames and moves.
    public let bundleID: String

    public init(keyCode: UInt16, modifiers: Set<Modifier>, bundleID: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.bundleID = bundleID
    }

    /// Identity is the key combination, because two bindings may never share one.
    public var id: String {
        "\(keyCode)-" + modifiers.sorted().map(\.rawValue).joined(separator: "+")
    }

    public func matches(keyCode: UInt16, modifiers: Set<Modifier>) -> Bool {
        self.keyCode == keyCode && self.modifiers == modifiers
    }

    public var displayKey: String {
        Hotkey(keyCode: keyCode, modifiers: modifiers).displayKey
    }
}
