import Foundation

/// Protocol for SwiftUI state management. The VM uses this to read/write @State
/// values without depending on SwiftUI directly. LanternSwiftUI provides the
/// concrete implementation (LanternStateStore).
public protocol StateStoreProtocol: AnyObject {
    func get(_ name: String) -> Value
    func set(_ name: String, _ value: Value)
    func contains(_ name: String) -> Bool
}

/// Protocol for collecting views during body evaluation.
/// The VM uses this to accumulate child views without depending on SwiftUI.
public protocol ViewCollectorProtocol: AnyObject {
    /// Called when a VIEW_COLLECT opcode fires — the VM passes the view value.
    func collectView(_ value: Value)
    /// Called when a VIEW_GROUP opcode fires — group the last N collected views.
    func groupViews(_ count: Int) -> Value
}

/// Context injected into the VM during SwiftUI view body evaluation.
/// Nil when running non-SwiftUI code.
public final class SwiftUIContext: @unchecked Sendable {
    public let stateStore: StateStoreProtocol
    public let viewCollector: ViewCollectorProtocol?

    public init(stateStore: StateStoreProtocol, viewCollector: ViewCollectorProtocol? = nil) {
        self.stateStore = stateStore
        self.viewCollector = viewCollector
    }
}
