#if canImport(SwiftUI)
import SwiftUI
import LanternVM

/// Wraps an interpreted class conforming to ObservableObject so SwiftUI
/// can observe its @Published properties.
///
/// Usage: when an interpreted class has @Published properties, wrap it in
/// LanternObservableWrapper. The VM's publishSet opcode calls propertyDidChange
/// which fires objectWillChange, triggering SwiftUI re-render.
public final class LanternObservableWrapper: ObservableObject {
    public let vm: VM
    public let instance: InstanceRef

    public init(vm: VM, instance: InstanceRef) {
        self.vm = vm
        self.instance = instance
    }

    /// Called by the VM when a @Published property is modified.
    public func propertyDidChange(_ name: String) {
        objectWillChange.send()
    }

    /// Read a property from the wrapped instance.
    public func get(_ name: String) -> Value {
        instance.property(name) ?? .nil_
    }

    /// Write a property on the wrapped instance (triggers objectWillChange).
    public func set(_ name: String, _ value: Value) {
        instance.setProperty(name, value)
        objectWillChange.send()
    }
}
#endif
