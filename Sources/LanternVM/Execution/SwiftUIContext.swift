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

/// Protocol for building a parallel view descriptor tree for debugging.
/// Minimal descriptor for a view in the hierarchy, used at the VM level.
public struct VMViewDescriptor: Sendable {
    public let typeName: String
    public let properties: [String: Value]
    public let modifierNames: [String]
    public let children: [VMViewDescriptor]

    public init(typeName: String, properties: [String: Value] = [:], modifierNames: [String] = [], children: [VMViewDescriptor] = []) {
        self.typeName = typeName; self.properties = properties
        self.modifierNames = modifierNames; self.children = children
    }
}

public protocol DescriptorBuilderProtocol: AnyObject {
    func beginView(typeName: String, properties: [String: Value], location: SourceLocation)
    func endView()
    func addModifier(name: String, arguments: [String: Value], location: SourceLocation)
    /// The root view descriptor, if the tree has been built.
    var rootViewDescriptor: VMViewDescriptor? { get }
}

/// Context injected into the VM during SwiftUI view body evaluation.
/// Nil when running non-SwiftUI code.
public final class SwiftUIContext: @unchecked Sendable {
    public let stateStore: StateStoreProtocol
    public let viewCollector: ViewCollectorProtocol?
    public let descriptorBuilder: DescriptorBuilderProtocol?
    /// Environment values provided by the host, readable via @Environment
    public var environmentValues: [String: Value] = [:]
    /// Maps @AppStorage property names to UserDefaults keys
    public var appStorageKeys: [String: String] = [:]

    public init(stateStore: StateStoreProtocol, viewCollector: ViewCollectorProtocol? = nil, descriptorBuilder: DescriptorBuilderProtocol? = nil) {
        self.stateStore = stateStore
        self.viewCollector = viewCollector
        self.descriptorBuilder = descriptorBuilder
    }
}

/// A reference to a @State binding, carrying the state store and key.
/// The SwiftUI bridge converts this to a real Binding<T> at the call site.
public final class BindingRef: @unchecked Sendable {
    public let stateStore: StateStoreProtocol
    public let key: String

    public init(stateStore: StateStoreProtocol, key: String) {
        self.stateStore = stateStore
        self.key = key
    }
}
