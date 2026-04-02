#if canImport(SwiftUI)
import SwiftUI
import LanternVM

/// Wraps an interpreted class conforming to ObservableObject so SwiftUI
/// can observe its @Published properties.
public final class LanternObservableWrapper: ObservableObject {
    public let vm: VM
    public let instance: InstanceRef

    public init(vm: VM, instance: InstanceRef) {
        self.vm = vm
        self.instance = instance
    }

    /// Called by the interpreter when a @Published property is modified
    /// via PUBLISH_SET. Fires objectWillChange.
    public func propertyDidChange(_ name: String) {
        objectWillChange.send()
    }
}
#endif
