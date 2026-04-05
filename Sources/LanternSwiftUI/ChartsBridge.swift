#if canImport(SwiftUI) && canImport(Charts)
import SwiftUI
import Charts
import LanternVM
import LanternBridge

/// Registers Swift Charts types for use in interpreted SwiftUI views.
public func registerChartsBridge(on registry: BridgeRegistry, vm: VM? = nil) {
    guard let vm = vm else { return }

    // Chart { marks... } — trailing closure produces chart data
    registry.registerType("Chart") { [weak vm] args in
        guard let vm else { return .nil_ }
        let closure = args.first(where: { if case .closure = $0 { return true }; return false })

        guard let closure else {
            return .hostObject(HostObjectRef(object: ViewBox(AnyView(Chart { })), typeName: "Chart"))
        }

        // Collect mark data by invoking the closure
        let collector = ChartDataCollector()
        let savedCollector = vm.environment.getGlobal("__chartCollector")
        vm.environment.setGlobal("__chartCollector", value: .hostObject(HostObjectRef(object: collector, typeName: "ChartCollector")))

        _ = try vm.invokeValue(closure, args: [])

        // Restore
        if let saved = savedCollector {
            vm.environment.setGlobal("__chartCollector", value: saved)
        }

        // Build Chart from collected data
        let entries = collector.entries
        let chartView = AnyView(
            Chart {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    switch entry.markType {
                    case "BarMark":
                        BarMark(
                            x: .value(entry.xLabel, entry.xString ?? ""),
                            y: .value(entry.yLabel, entry.yValue)
                        )
                    case "LineMark":
                        LineMark(
                            x: .value(entry.xLabel, entry.xValue),
                            y: .value(entry.yLabel, entry.yValue)
                        )
                    case "PointMark":
                        PointMark(
                            x: .value(entry.xLabel, entry.xValue),
                            y: .value(entry.yLabel, entry.yValue)
                        )
                    case "RuleMark":
                        RuleMark(y: .value(entry.yLabel, entry.yValue))
                    default:
                        BarMark(
                            x: .value(entry.xLabel, entry.xString ?? ""),
                            y: .value(entry.yLabel, entry.yValue)
                        )
                    }
                }
            }
        )
        return .hostObject(HostObjectRef(object: ViewBox(chartView), typeName: "Chart"))
    }

    // Mark constructors — store data in the active ChartDataCollector
    for markType in ["BarMark", "LineMark", "PointMark", "RuleMark"] {
        registry.registerType(markType) { [weak vm] args in
            guard let vm else { return .nil_ }
            // Get active collector
            if case .hostObject(let ref) = vm.environment.getGlobal("__chartCollector"),
               let collector = ref.object as? ChartDataCollector {
                var entry = ChartEntry(markType: markType)
                if args.count >= 2 {
                    // x, y values
                    entry.xLabel = args[0].stringValue ?? "X"
                    entry.xString = args[0].stringValue
                    entry.xValue = args[0].doubleValue ?? Double(args[0].intValue ?? 0)
                    entry.yLabel = "Value"
                    entry.yValue = args[1].doubleValue ?? Double(args[1].intValue ?? 0)
                } else if args.count == 1 {
                    entry.yValue = args[0].doubleValue ?? Double(args[0].intValue ?? 0)
                }
                collector.entries.append(entry)
            }
            // Return a placeholder — the actual mark is built inside Chart
            return .void
        }
    }
}

// MARK: - Chart Data Types

struct ChartEntry {
    var markType: String
    var xLabel: String = "X"
    var yLabel: String = "Y"
    var xValue: Double = 0
    var yValue: Double = 0
    var xString: String? = nil
    var series: String? = nil
}

final class ChartDataCollector: @unchecked Sendable {
    var entries: [ChartEntry] = []
}
#endif
