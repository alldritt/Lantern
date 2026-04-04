#if canImport(SwiftUI)
import SwiftUI
import LanternVM

/// Accumulates child views during @ViewBuilder closure evaluation.
/// Conforms to ViewCollectorProtocol so the VM's pop opcode can
/// collect view values instead of discarding them.
public final class ViewCollector: ViewCollectorProtocol {
    public var views: [AnyView] = []
    public var descriptors: [ViewDescriptor] = []

    public init() {}

    public func add(_ view: AnyView, descriptor: ViewDescriptor) {
        views.append(view)
        descriptors.append(descriptor)
    }

    /// Called by VM's pop opcode when collector is active.
    /// Only collects hostObject ViewBox values (actual views).
    public func collectView(_ value: Value) {
        if case .hostObject(let ref) = value, let box = ref.object as? ViewBox {
            views.append(box.view)
        }
    }

    /// Group the last N collected views into a single container value.
    public func groupViews(_ count: Int) -> Value {
        let grouped = Array(views.suffix(count))
        views.removeLast(min(count, views.count))
        let combined = AnyView(ForEach(Array(grouped.enumerated()), id: \.offset) { _, v in v })
        return .hostObject(HostObjectRef(object: ViewBox(combined), typeName: "Group"))
    }

    /// Combine all collected views into a single AnyView.
    public func buildCombinedView() -> AnyView {
        if views.isEmpty {
            return AnyView(EmptyView())
        }
        if views.count == 1 {
            return views[0]
        }
        let allViews = views
        return AnyView(
            ForEach(Array(allViews.enumerated()), id: \.offset) { _, view in
                view
            }
        )
    }

    public var count: Int { views.count }
    public var isEmpty: Bool { views.isEmpty }

    public func clear() {
        views.removeAll()
        descriptors.removeAll()
    }
}
#endif
