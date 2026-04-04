#if canImport(SwiftUI)
import SwiftUI
import LanternVM

/// Host-side SwiftUI view that wraps an interpreted view instance.
/// The body delegates to the interpreter for view tree evaluation.
public struct ViewStub: View {
    let vm: VM
    let instance: InstanceRef

    @StateObject private var stateStore = LanternStateStore()

    public init(vm: VM, instance: InstanceRef) {
        self.vm = vm
        self.instance = instance
    }

    public var body: some View {
        evaluateBody()
    }

    private func evaluateBody() -> AnyView {
        // Set up SwiftUI context so @State opcodes work
        let previousContext = vm.swiftUIContext
        vm.swiftUIContext = SwiftUIContext(stateStore: stateStore)
        defer { vm.swiftUIContext = previousContext }

        // Look up the body computed property getter: TypeName.__get_body
        let getterName = "\(instance.typeName).__get_body"
        guard let getter = vm.environment.getGlobal(getterName) else {
            return AnyView(Text("No body defined for \(instance.typeName)"))
        }

        // Evaluate the body by invoking the getter with self = instance
        do {
            let result = try vm.invokeValue(getter, args: [.instance(instance)])
            return ViewFactory.viewFromValue(result)
        } catch {
            return AnyView(Text("Error: \(error)"))
        }
    }
}
#endif
