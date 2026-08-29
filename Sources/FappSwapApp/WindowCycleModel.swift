import Foundation

/// The ⌥⇥ window-cycling toggle. A missing key reads as enabled, so the
/// feature is on from first install without writing anything.
final class WindowCycleModel {
    static let defaultsKey = "windowCycleEnabled"

    static var storedEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.defaultsKey)
            onChange(enabled)
        }
    }

    private let onChange: (Bool) -> Void

    init(onChange: @escaping (Bool) -> Void) {
        enabled = Self.storedEnabled
        self.onChange = onChange
    }
}
