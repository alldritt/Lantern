#if canImport(SwiftUI)
import SwiftUI
import LanternVM

/// Holds @State values for an interpreted view. Integrates with SwiftUI's
/// observation system through ObservableObject.
///
/// Also supports @AppStorage: properties mapped to UserDefaults keys are
/// read/written through UserDefaults and synced on change.
public final class LanternStateStore: ObservableObject, StateStoreProtocol {
    @Published public var values: [String: Value] = [:]

    /// Maps @State property names to UserDefaults keys for @AppStorage support.
    /// e.g., ["darkMode": "darkMode", "username": "user_name"]
    public var appStorageKeys: [String: String] = [:]

    public init() {}

    public func get(_ name: String) -> Value {
        // Check if this is an @AppStorage property
        if let udKey = appStorageKeys[name] {
            return readFromUserDefaults(key: udKey)
        }
        return values[name] ?? .nil_
    }

    public func set(_ name: String, _ value: Value) {
        values[name] = value
        // If @AppStorage, also write to UserDefaults
        if let udKey = appStorageKeys[name] {
            writeToUserDefaults(key: udKey, value: value)
        }
    }

    public func contains(_ name: String) -> Bool {
        if appStorageKeys[name] != nil { return true }
        return values[name] != nil
    }

    public var allKeys: [String] { Array(values.keys) }

    public var snapshot: [String: Value] { values }

    // MARK: - UserDefaults Integration

    private func readFromUserDefaults(key: String) -> Value {
        let defaults = UserDefaults.standard
        if let s = defaults.string(forKey: key) { return .string(s) }
        let i = defaults.integer(forKey: key)
        if i != 0 || defaults.object(forKey: key) is Int { return .int(i) }
        let d = defaults.double(forKey: key)
        if d != 0 || defaults.object(forKey: key) is Double { return .double(d) }
        let b = defaults.bool(forKey: key)
        if b || defaults.object(forKey: key) is Bool { return .bool(b) }
        // Fall back to in-memory value
        return values[key] ?? .nil_
    }

    private func writeToUserDefaults(key: String, value: Value) {
        let defaults = UserDefaults.standard
        switch value {
        case .string(let s): defaults.set(s, forKey: key)
        case .int(let i): defaults.set(i, forKey: key)
        case .double(let d): defaults.set(d, forKey: key)
        case .bool(let b): defaults.set(b, forKey: key)
        case .nil_: defaults.removeObject(forKey: key)
        default: defaults.set(value.description, forKey: key)
        }
    }
}
#endif
