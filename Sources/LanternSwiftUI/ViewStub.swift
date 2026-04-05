#if canImport(SwiftUI)
import SwiftUI
import LanternVM

/// Host-side SwiftUI view that wraps an interpreted view instance.
/// The body delegates to the interpreter for view tree evaluation.
public struct ViewStub: View {
    let vm: VM
    let instance: InstanceRef
    let appStorageKeys: [String: String]

    @ObservedObject var stateStore: LanternStateStore
    @SwiftUI.Environment(\.colorScheme) private var colorScheme
    @SwiftUI.Environment(\.horizontalSizeClass) private var sizeClass

    private let descriptorBuilder = ViewDescriptorBuilder()

    /// The view descriptor tree from the last evaluation, for debugger inspection.
    public var lastDescriptor: ViewDescriptor? { descriptorBuilder.rootDescriptor }

    public init(vm: VM, instance: InstanceRef, stateStore: LanternStateStore = LanternStateStore(), appStorageKeys: [String: String] = [:]) {
        self.vm = vm
        self.instance = instance
        self.stateStore = stateStore
        self.appStorageKeys = appStorageKeys
    }

    public var body: some View {
        evaluateBody()
    }

    private func evaluateBody() -> AnyView {
        let previousContext = vm.swiftUIContext
        descriptorBuilder.reset()
        let ctx = SwiftUIContext(stateStore: stateStore, descriptorBuilder: descriptorBuilder)

        // Wire @AppStorage key mappings
        ctx.appStorageKeys = appStorageKeys

        // Populate @Environment values from the real SwiftUI environment
        ctx.environmentValues["colorScheme"] = colorScheme == .dark ? .string("dark") : .string("light")
        #if os(iOS)
        ctx.environmentValues["horizontalSizeClass"] = sizeClass == .compact ? .string("compact") : .string("regular")
        #endif

        // Seed @State default values from instance properties (first render only)
        for name in instance.propertyNames {
            if !stateStore.contains(name), let value = instance.property(name) {
                stateStore.set(name, value)
            }
        }

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
