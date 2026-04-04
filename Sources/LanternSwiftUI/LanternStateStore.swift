#if canImport(SwiftUI)
import SwiftUI
import LanternVM

/// Holds @State values for an interpreted view. Integrates with SwiftUI's
/// observation system through ObservableObject.
public final class LanternStateStore: ObservableObject, StateStoreProtocol {
    @Published public var values: [String: Value] = [:]

    public init() {}

    public func get(_ name: String) -> Value { values[name] ?? .nil_ }

    public func set(_ name: String, _ value: Value) { values[name] = value }

    public func contains(_ name: String) -> Bool { values[name] != nil }

    public var allKeys: [String] { Array(values.keys) }

    public var snapshot: [String: Value] { values }
}
#endif
