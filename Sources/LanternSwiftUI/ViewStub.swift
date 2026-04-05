#if canImport(SwiftUI)
import SwiftUI
import LanternVM

/// Host-side SwiftUI view that wraps an interpreted view instance.
/// The body delegates to the interpreter for view tree evaluation.
public struct ViewStub: View {
    let vm: VM
    let instance: InstanceRef

    @StateObject private var stateStore = LanternStateStore()
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    @SwiftUI.Environment(\.horizontalSizeClass) private var sizeClass

    private let descriptorBuilder = ViewDescriptorBuilder()

    /// The view descriptor tree from the last evaluation, for debugger inspection.
    public var lastDescriptor: ViewDescriptor? { descriptorBuilder.rootDescriptor }

    public init(vm: VM, instance: InstanceRef) {
        self.vm = vm
        self.instance = instance
    }

    public var body: some View {
        evaluateBody()
    }

    private func evaluateBody() -> AnyView {
        let previousContext = vm.swiftUIContext
        descriptorBuilder.reset()
        let ctx = SwiftUIContext(stateStore: stateStore, descriptorBuilder: descriptorBuilder)

        // Populate @Environment values from the real SwiftUI environment
        ctx.environmentValues["colorScheme"] = colorScheme == .dark ? .string("dark") : .string("light")
        #if os(iOS)
        ctx.environmentValues["horizontalSizeClass"] = sizeClass == .compact ? .string("compact") : .string("regular")
        #endif

        vm.swiftUIContext = ctx
        defer { vm.swiftUIContext = previousContext }

        let getterName = "\(instance.typeName).__get_body"
        guard let getter = vm.environment.getGlobal(getterName) else {
            return AnyView(Text("No body defined for \(instance.typeName)"))
        }

        do {
            let result = try vm.invokeValue(getter, args: [.instance(instance)])
            return ViewFactory.viewFromValue(result)
        } catch {
            return AnyView(Text("Error: \(error)"))
        }
    }
}
#endif
