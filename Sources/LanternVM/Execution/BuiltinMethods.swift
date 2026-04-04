import Foundation

/// Signature for built-in method implementations.
/// The VM is passed for re-entrant closure invocation (map/filter/reduce callbacks).
public typealias BuiltinMethodImpl = (_ vm: VM, _ receiver: Value, _ args: [Value]) throws -> Value

/// Registry of built-in methods for primitive types (Array, String, Dictionary, Range, Optional).
/// Extracted from VM.callMethod to make the VM extensible and the methods individually testable.
public final class BuiltinMethodRegistry {
    private var methods: [String: [String: BuiltinMethodImpl]] = [:]

    public init() {
        registerArrayMethods()
        registerStringMethods()
        registerDictionaryMethods()
        registerOptionalMethods()
        registerRangeMethods()
    }

    public func lookup(_ typeName: String, _ methodName: String) -> BuiltinMethodImpl? {
        methods[typeName]?[methodName]
    }

    private func register(_ typeName: String, _ name: String, _ impl: @escaping BuiltinMethodImpl) {
        if methods[typeName] == nil { methods[typeName] = [:] }
        methods[typeName]![name] = impl
    }

    // MARK: - Array Methods

    private func registerArrayMethods() {
        register("Array", "append") { _, receiver, args in
            guard case .array(var arr) = receiver, let elem = args.first else { return receiver }
            arr.append(elem)
            return .array(arr)
        }
        register("Array", "contains") { vm, receiver, args in
            guard case .array(let arr) = receiver, let elem = args.first else { return .bool(false) }
            if case .closure = elem {
                for item in arr {
                    let res = try vm.invokeValue(elem, args: [item])
                    if case .bool(true) = res { return .bool(true) }
                }
                return .bool(false)
            }
            return .bool(arr.contains(elem))
        }
        register("Array", "reversed") { _, receiver, _ in
            guard case .array(let arr) = receiver else { return receiver }
            return .array(arr.reversed())
        }
        register("Array", "removeLast") { _, receiver, _ in
            guard case .array(var arr) = receiver else { return receiver }
            _ = arr.popLast()
            return .array(arr)
        }
        register("Array", "remove") { _, receiver, args in
            guard case .array(var arr) = receiver,
                  case .int(let idx) = args.first, idx >= 0 && idx < arr.count else { return receiver }
            arr.remove(at: idx)
            return .array(arr)
        }
        register("Array", "sorted") { vm, receiver, args in
            guard case .array(let arr) = receiver else { return receiver }
            if let comparator = args.first {
                var mutableArr = arr
                for i in 0..<mutableArr.count {
                    for j in 0..<(mutableArr.count - 1 - i) {
                        let cmpResult = try vm.invokeValue(comparator, args: [mutableArr[j+1], mutableArr[j]])
                        if case .bool(let shouldSwap) = cmpResult, shouldSwap {
                            mutableArr.swapAt(j, j+1)
                        }
                    }
                }
                return .array(mutableArr)
            }
            // Check for user-defined < operator
            if let first = arr.first, case .instance(let ref) = first,
               let lessThan = vm.environment.getGlobal("\(ref.typeName).<") {
                var mutableArr = arr
                for i in 0..<mutableArr.count {
                    for j in 0..<(mutableArr.count - 1 - i) {
                        let cmpResult = try vm.invokeValue(lessThan, args: [mutableArr[j+1], mutableArr[j]])
                        if case .bool(true) = cmpResult { mutableArr.swapAt(j, j+1) }
                    }
                }
                return .array(mutableArr)
            }
            return .array(arr.sorted { a, b in
                if let la = a.intValue, let lb = b.intValue { return la < lb }
                if let la = a.doubleValue, let lb = b.doubleValue { return la < lb }
                if case .string(let la) = a, case .string(let lb) = b { return la < lb }
                return false
            })
        }
        register("Array", "joined") { _, receiver, args in
            guard case .array(let arr) = receiver else { return .string("") }
            let sep = args.first?.stringValue ?? ""
            return .string(arr.compactMap { $0.stringValue }.joined(separator: sep))
        }
        register("Array", "map") { vm, receiver, args in
            guard case .array(let arr) = receiver, let closureVal = args.first else { return .array([]) }
            var mapped: [Value] = []
            for elem in arr {
                let callArgs: [Value]
                if case .closure(let ref) = closureVal, ref.function.parameters.count > 1,
                   case .array(let pair) = elem {
                    callArgs = pair
                } else {
                    callArgs = [elem]
                }
                mapped.append(try vm.invokeValue(closureVal, args: callArgs))
            }
            return .array(mapped)
        }
        register("Array", "filter") { vm, receiver, args in
            guard case .array(let arr) = receiver, let closureVal = args.first else { return receiver }
            var filtered: [Value] = []
            for elem in arr {
                if try vm.invokeValue(closureVal, args: [elem]).isTruthy { filtered.append(elem) }
            }
            return .array(filtered)
        }
        register("Array", "forEach") { vm, receiver, args in
            guard case .array(let arr) = receiver, let closureVal = args.first else { return .void }
            for elem in arr { _ = try vm.invokeValue(closureVal, args: [elem]) }
            return .void
        }
        register("Array", "reduce") { vm, receiver, args in
            guard case .array(let arr) = receiver, args.count >= 2 else { return .nil_ }
            var acc = args[0]
            let closureVal = args[1]
            for elem in arr { acc = try vm.invokeValue(closureVal, args: [acc, elem]) }
            return acc
        }
        register("Array", "enumerated") { _, receiver, _ in
            guard case .array(let arr) = receiver else { return .array([]) }
            return .array(arr.enumerated().map { .array([.int($0.offset), $0.element]) })
        }
        register("Array", "allSatisfy") { vm, receiver, args in
            guard case .array(let arr) = receiver, let pred = args.first else { return .bool(true) }
            for item in arr {
                if case .bool(false) = try vm.invokeValue(pred, args: [item]) { return .bool(false) }
            }
            return .bool(true)
        }
        register("Array", "compactMap") { vm, receiver, args in
            guard case .array(let arr) = receiver, let transform = args.first else { return receiver }
            var mapped: [Value] = []
            for item in arr {
                let res = try vm.invokeValue(transform, args: [item])
                if !res.isNil {
                    if case .optional(let inner) = res, let v = inner { mapped.append(v) }
                    else { mapped.append(res) }
                }
            }
            return .array(mapped)
        }
        register("Array", "flatMap") { vm, receiver, args in
            guard case .array(let arr) = receiver, let transform = args.first else { return receiver }
            var mapped: [Value] = []
            for item in arr {
                let res = try vm.invokeValue(transform, args: [item])
                if case .array(let inner) = res { mapped.append(contentsOf: inner) }
                else { mapped.append(res) }
            }
            return .array(mapped)
        }
        register("Array", "min") { vm, receiver, args in
            guard case .array(let arr) = receiver else { return .nil_ }
            if let comparator = args.first {
                var minVal = arr.first ?? .nil_
                for item in arr.dropFirst() {
                    if case .bool(true) = try vm.invokeValue(comparator, args: [item, minVal]) { minVal = item }
                }
                return .optional(minVal)
            }
            let sorted = arr.sorted { a, b in
                if let la = a.intValue, let lb = b.intValue { return la < lb }
                if let la = a.doubleValue, let lb = b.doubleValue { return la < lb }
                return false
            }
            return .optional(sorted.first)
        }
        register("Array", "max") { vm, receiver, args in
            guard case .array(let arr) = receiver else { return .nil_ }
            if let comparator = args.first {
                var maxVal = arr.first ?? .nil_
                for item in arr.dropFirst() {
                    if case .bool(true) = try vm.invokeValue(comparator, args: [maxVal, item]) { maxVal = item }
                }
                return .optional(maxVal)
            }
            let sorted = arr.sorted { a, b in
                if let la = a.intValue, let lb = b.intValue { return la > lb }
                if let la = a.doubleValue, let lb = b.doubleValue { return la > lb }
                return false
            }
            return .optional(sorted.first)
        }
        register("Array", "first") { vm, receiver, args in
            guard case .array(let arr) = receiver else { return .nil_ }
            if let predicate = args.first {
                for item in arr {
                    if case .bool(true) = try vm.invokeValue(predicate, args: [item]) { return .optional(item) }
                }
                return .optional(nil)
            }
            return .optional(arr.first)
        }
        register("Array", "last") { vm, receiver, args in
            guard case .array(let arr) = receiver else { return .nil_ }
            if let predicate = args.first {
                for item in arr.reversed() {
                    if case .bool(true) = try vm.invokeValue(predicate, args: [item]) { return .optional(item) }
                }
                return .optional(nil)
            }
            return .optional(arr.last)
        }
        register("Array", "dropFirst") { _, receiver, args in
            guard case .array(let arr) = receiver else { return receiver }
            return .array(Array(arr.dropFirst(args.first?.intValue ?? 1)))
        }
        register("Array", "dropLast") { _, receiver, args in
            guard case .array(let arr) = receiver else { return receiver }
            return .array(Array(arr.dropLast(args.first?.intValue ?? 1)))
        }
        register("Array", "prefix") { _, receiver, args in
            guard case .array(let arr) = receiver else { return receiver }
            return .array(Array(arr.prefix(args.first?.intValue ?? 0)))
        }
        register("Array", "suffix") { _, receiver, args in
            guard case .array(let arr) = receiver else { return receiver }
            return .array(Array(arr.suffix(args.first?.intValue ?? 0)))
        }
    }

    // MARK: - String Methods

    private func registerStringMethods() {
        register("String", "uppercased") { _, receiver, _ in
            guard case .string(let s) = receiver else { return receiver }
            return .string(s.uppercased())
        }
        register("String", "lowercased") { _, receiver, _ in
            guard case .string(let s) = receiver else { return receiver }
            return .string(s.lowercased())
        }
        register("String", "hasPrefix") { _, receiver, args in
            guard case .string(let s) = receiver, case .string(let p) = args.first else { return .bool(false) }
            return .bool(s.hasPrefix(p))
        }
        register("String", "hasSuffix") { _, receiver, args in
            guard case .string(let s) = receiver, case .string(let p) = args.first else { return .bool(false) }
            return .bool(s.hasSuffix(p))
        }
        register("String", "contains") { _, receiver, args in
            guard case .string(let s) = receiver, case .string(let sub) = args.first else { return .bool(false) }
            return .bool(s.contains(sub))
        }
        register("String", "replacingOccurrences") { _, receiver, args in
            guard case .string(let s) = receiver, args.count >= 2,
                  case .string(let target) = args[0], case .string(let repl) = args[1] else { return receiver }
            return .string(s.replacingOccurrences(of: target, with: repl))
        }
        register("String", "split") { _, receiver, args in
            guard case .string(let s) = receiver, case .string(let sep) = args.first else { return .array([]) }
            return .array(s.split(separator: sep).map { .string(String($0)) })
        }
        register("String", "trimmingCharacters") { _, receiver, _ in
            guard case .string(let s) = receiver else { return receiver }
            return .string(s.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        register("String", "reversed") { _, receiver, _ in
            guard case .string(let s) = receiver else { return receiver }
            return .array(s.reversed().map { .string(String($0)) })
        }
    }

    // MARK: - Dictionary Methods

    private func registerDictionaryMethods() {
        register("Dictionary", "removeValue") { _, receiver, args in
            guard case .dictionary(var d) = receiver, case .string(let key) = args.first else { return receiver }
            d.removeValue(forKey: key)
            return .dictionary(d)
        }
        register("Dictionary", "compactMapValues") { vm, receiver, args in
            guard case .dictionary(let d) = receiver, let transform = args.first else { return receiver }
            var newDict: [String: Value] = [:]
            for (key, value) in d {
                let mapped = try vm.invokeValue(transform, args: [value])
                switch mapped {
                case .nil_, .optional(.none): continue
                case .optional(.some(let inner)): newDict[key] = inner
                default: newDict[key] = mapped
                }
            }
            return .dictionary(newDict)
        }
        register("Dictionary", "sorted") { vm, receiver, args in
            guard case .dictionary(let d) = receiver else { return receiver }
            let pairs: [Value] = d.map { .array([.string($0.key), $0.value]) }
            if let comparator = args.first {
                var mutablePairs = pairs
                for i in 0..<mutablePairs.count {
                    for j in 0..<(mutablePairs.count - 1 - i) {
                        let cmpResult = try vm.invokeValue(comparator, args: [mutablePairs[j], mutablePairs[j+1]])
                        if case .bool(false) = cmpResult { mutablePairs.swapAt(j, j+1) }
                    }
                }
                return .array(mutablePairs)
            }
            return .array(pairs.sorted { a, b in
                guard case .array(let pa) = a, case .array(let pb) = b,
                      case .string(let ka) = pa[0], case .string(let kb) = pb[0] else { return false }
                return ka < kb
            })
        }
    }

    // MARK: - Optional Methods

    private func registerOptionalMethods() {
        register("Optional", "map") { vm, receiver, args in
            guard case .optional(.some(let inner)) = receiver, let transform = args.first else {
                return .nil_
            }
            let mapped = try vm.invokeValue(transform, args: [inner])
            return .optional(mapped)
        }
        register("Optional", "flatMap") { vm, receiver, args in
            guard case .optional(.some(let inner)) = receiver, let transform = args.first else {
                return .nil_
            }
            let mapped = try vm.invokeValue(transform, args: [inner])
            if case .optional = mapped { return mapped }
            if case .nil_ = mapped { return .nil_ }
            return .optional(mapped)
        }
    }

    // MARK: - Range Methods

    private func registerRangeMethods() {
        register("Range", "contains") { _, receiver, args in
            guard case .range(let start, let end, let inclusive) = receiver,
                  let val = args.first?.intValue else { return .bool(false) }
            return .bool(inclusive ? (val >= start && val <= end) : (val >= start && val < end))
        }
        register("Range", "map") { vm, receiver, args in
            guard case .range(let start, let end, let inclusive) = receiver,
                  let closureVal = args.first else { return .array([]) }
            let rangeEnd = inclusive ? end : end - 1
            var mapped: [Value] = []
            for i in start...rangeEnd {
                mapped.append(try vm.invokeValue(closureVal, args: [.int(i)]))
            }
            return .array(mapped)
        }
        register("Range", "filter") { vm, receiver, args in
            guard case .range(let start, let end, let inclusive) = receiver,
                  let closureVal = args.first else { return .array([]) }
            let rangeEnd = inclusive ? end : end - 1
            var filtered: [Value] = []
            for i in start...rangeEnd {
                let val = Value.int(i)
                if try vm.invokeValue(closureVal, args: [val]).isTruthy { filtered.append(val) }
            }
            return .array(filtered)
        }
        register("Range", "reduce") { vm, receiver, args in
            guard case .range(let start, let end, let inclusive) = receiver,
                  args.count >= 2 else { return .nil_ }
            let rangeEnd = inclusive ? end : end - 1
            var acc = args[0]
            let closureVal = args[1]
            for i in start...rangeEnd {
                acc = try vm.invokeValue(closureVal, args: [acc, .int(i)])
            }
            return acc
        }
        register("Range", "forEach") { vm, receiver, args in
            guard case .range(let start, let end, let inclusive) = receiver,
                  let closureVal = args.first else { return .void }
            let rangeEnd = inclusive ? end : end - 1
            for i in start...rangeEnd { _ = try vm.invokeValue(closureVal, args: [.int(i)]) }
            return .void
        }
    }
}
