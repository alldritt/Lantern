#if canImport(SwiftUI)
import SwiftUI
import LanternVM

/// Host-side SwiftUI view that wraps an interpreted view instance.
/// The body delegates to the interpreter for evaluation.
public struct ViewStub: View {
    let vm: VM
    let instance: InstanceRef

    @StateObject private var stateStore = LanternStateStore()

    public init(vm: VM, instance: InstanceRef) {
        self.vm = vm
        self.instance = instance
    }

    public var body: some View {
        // In a full implementation, vm.evaluateViewBody(of: instance, stateStore: stateStore)
        // returns a real AnyView tree. For now, placeholder.
        Text("Interpreted: \(instance.typeName)")
    }
}
#endif
