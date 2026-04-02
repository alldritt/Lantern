#if canImport(SwiftUI)
import SwiftUI
import LanternVM

/// Accumulates child views during @ViewBuilder closure evaluation.
public final class ViewCollector {
    public private(set) var views: [AnyView] = []
    public private(set) var descriptors: [ViewDescriptor] = []

    public init() {}

    public func add(_ view: AnyView, descriptor: ViewDescriptor) {
        views.append(view)
        descriptors.append(descriptor)
    }

    public var count: Int { views.count }
    public var isEmpty: Bool { views.isEmpty }

    public func clear() {
        views.removeAll()
        descriptors.removeAll()
    }
}
#endif
