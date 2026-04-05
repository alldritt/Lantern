#if canImport(SwiftUI) && canImport(MapKit)
import SwiftUI
import MapKit
import LanternVM
import LanternBridge

/// Registers MapKit SwiftUI views for use in interpreted code.
public func registerMapKitBridge(on registry: BridgeRegistry, vm: VM? = nil) {
    // Map() — basic map view
    registry.registerType("Map") { args in
        let view: AnyView
        if args.isEmpty {
            view = AnyView(Map())
        } else {
            view = AnyView(Map())
        }
        return .hostObject(HostObjectRef(object: ViewBox(view), typeName: "Map"))
    }

    // CLLocationCoordinate2D as a bridged type
    registry.registerType("CLLocationCoordinate2D") { args in
        guard args.count >= 2,
              let lat = args[0].doubleValue,
              let lon = args[1].doubleValue else { return .nil_ }
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return .hostObject(HostObjectRef(object: CoordinateBox(coord), typeName: "CLLocationCoordinate2D"))
    }

    registry.registerProperty(typeName: "CLLocationCoordinate2D", name: "latitude", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let box = ref.object as? CoordinateBox else { return .nil_ }
        return .double(box.coordinate.latitude)
    }, setter: nil)

    registry.registerProperty(typeName: "CLLocationCoordinate2D", name: "longitude", getter: { receiver in
        guard let ref = receiver.hostObjectRef, let box = ref.object as? CoordinateBox else { return .nil_ }
        return .double(box.coordinate.longitude)
    }, setter: nil)
}

/// Box for CLLocationCoordinate2D (a value type) so it can be stored in HostObjectRef.
private final class CoordinateBox: @unchecked Sendable {
    let coordinate: CLLocationCoordinate2D
    init(_ coord: CLLocationCoordinate2D) { self.coordinate = coord }
}
#endif
