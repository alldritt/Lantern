import Foundation

/// Signature for built-in method implementations.
/// The VM is passed for re-entrant closure invocation (map/filter/reduce callbacks).
public typealias BuiltinMethodImpl = (_ vm: VM, _ receiver: Value, _ args: [Value]) throws -> Value

/// Registry of built-in methods for primitive types (Array, String, Dictionary, Range, Optional).
/// Extracted from VM.callMethod to make the VM extensible and the methods individually testable.
public final class BuiltinMethodRegistry {
    private var methods: [String: [String: BuiltinMethodImpl]] = [:]

    public init() {
        registerIntMethods()
        registerDoubleMethods()
        registerBoolMethods()
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

    // MARK: - Int Methods

    private func registerIntMethods() {
        register("Int", "isMultiple") { _, receiver, args in
            guard let n = receiver.intValue, let of = args.first?.intValue, of != 0 else { return .bool(false) }
            return .bool(n.isMultiple(of: of))
        }
        register("Int", "signum") { _, receiver, _ in
            guard let n = receiver.intValue else { return .int(0) }
            return .int(n.signum())
        }
        register("Int", "magnitude") { _, receiver, _ in
            guard let n = receiver.intValue else { return .int(0) }
            return .int(Int(n.magnitude))
        }
        register("Int", "description") { _, receiver, _ in
            guard let n = receiver.intValue else { return .string("") }
            return .string(String(n))
        }
    }

    // MARK: - Double Methods

    private func registerDoubleMethods() {
        register("Double", "isNaN") { _, receiver, _ in
            guard let d = receiver.doubleValue else { return .bool(false) }
            return .bool(d.isNaN)
        }
        register("Double", "isInfinite") { _, receiver, _ in
            guard let d = receiver.doubleValue else { return .bool(false) }
            return .bool(d.isInfinite)
        }
        register("Double", "isFinite") { _, receiver, _ in
            guard let d = receiver.doubleValue else { return .bool(false) }
            return .bool(d.isFinite)
        }
        register("Double", "isZero") { _, receiver, _ in
            guard let d = receiver.doubleValue else { return .bool(false) }
            return .bool(d.isZero)
        }
        register("Double", "rounded") { _, receiver, _ in
            guard let d = receiver.doubleValue else { return .double(0) }
            return .double(d.rounded())
        }
        register("Double", "squareRoot") { _, receiver, _ in
            guard let d = receiver.doubleValue else { return .double(0) }
            return .double(d.squareRoot())
        }
        register("Double", "truncatingRemainder") { _, receiver, args in
            guard let d = receiver.doubleValue, let divisor = args.first?.doubleValue else { return .double(0) }
            return .double(d.truncatingRemainder(dividingBy: divisor))
        }
        register("Double", "description") { _, receiver, _ in
            guard let d = receiver.doubleValue else { return .string("") }
            return .string(String(d))
        }
    }

    // MARK: - Bool Methods

    private func registerBoolMethods() {
        register("Bool", "toggle") { _, receiver, _ in
            guard let b = receiver.boolValue else { return .bool(false) }
            return .bool(!b)
        }
        register("Bool", "description") { _, receiver, _ in
            guard let b = receiver.boolValue else { return .string("") }
            return .string(String(b))
        }
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
        register("Array", "insert") { _, receiver, args in
            guard case .array(var arr) = receiver, args.count >= 2,
                  let index = args[1].intValue else { return receiver }
            arr.insert(args[0], at: min(index, arr.count))
            return .array(arr)
        }
        register("Array", "removeAll") { _, receiver, _ in
            guard case .array = receiver else { return receiver }
            return .array([])
        }
        register("Array", "shuffle") { _, receiver, _ in
            guard case .array(var arr) = receiver else { return receiver }
            arr.shuffle()
            return .array(arr)
        }
        register("Array", "shuffled") { _, receiver, _ in
            guard case .array(let arr) = receiver else { return receiver }
            return .array(arr.shuffled())
        }
        register("Array", "randomElement") { _, receiver, _ in
            guard case .array(let arr) = receiver, let elem = arr.randomElement() else { return .nil_ }
            return elem
        }
        register("Array", "firstIndex") { vm, receiver, args in
            guard case .array(let arr) = receiver, let target = args.first else { return .nil_ }
            if case .closure = target {
                for (i, item) in arr.enumerated() {
                    let result = try vm.invokeValue(target, args: [item])
                    if result.isTruthy { return .int(i) }
                }
                return .nil_
            }
            if let idx = arr.firstIndex(where: { $0 == target }) { return .int(idx) }
            return .nil_
        }
        register("Array", "lastIndex") { vm, receiver, args in
            guard case .array(let arr) = receiver, let target = args.first else { return .nil_ }
            if case .closure = target {
                for i in stride(from: arr.count - 1, through: 0, by: -1) {
                    let result = try vm.invokeValue(target, args: [arr[i]])
                    if result.isTruthy { return .int(i) }
                }
                return .nil_
            }
            if let idx = arr.lastIndex(where: { $0 == target }) { return .int(idx) }
            return .nil_
        }
        register("Array", "swapAt") { _, receiver, args in
            guard case .array(var arr) = receiver, args.count >= 2,
                  let i = args[0].intValue, let j = args[1].intValue,
                  i >= 0, j >= 0, i < arr.count, j < arr.count else { return receiver }
            arr.swapAt(i, j)
            return .array(arr)
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
        register("String", "dropFirst") { _, receiver, args in
            guard case .string(let s) = receiver else { return receiver }
            let n = args.first?.intValue ?? 1
            return .string(String(s.dropFirst(n)))
        }
        register("String", "dropLast") { _, receiver, args in
            guard case .string(let s) = receiver else { return receiver }
            let n = args.first?.intValue ?? 1
            return .string(String(s.dropLast(n)))
        }
        register("String", "prefix") { _, receiver, args in
            guard case .string(let s) = receiver, let n = args.first?.intValue else { return receiver }
            return .string(String(s.prefix(n)))
        }
        register("String", "suffix") { _, receiver, args in
            guard case .string(let s) = receiver, let n = args.first?.intValue else { return receiver }
            return .string(String(s.suffix(n)))
        }
        register("String", "firstIndex") { _, receiver, args in
            guard case .string(let s) = receiver, let target = args.first?.stringValue?.first else { return .nil_ }
            if let idx = s.firstIndex(of: target) { return .int(s.distance(from: s.startIndex, to: idx)) }
            return .nil_
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
        register("Dictionary", "removeAll") { _, receiver, _ in
            guard case .dictionary = receiver else { return receiver }
            return .dictionary([:])
        }
        register("Dictionary", "mapValues") { vm, receiver, args in
            guard case .dictionary(let d) = receiver, let transform = args.first else { return receiver }
            var result: [String: Value] = [:]
            for (key, value) in d {
                result[key] = try vm.invokeValue(transform, args: [value])
            }
            return .dictionary(result)
        }
        register("Dictionary", "filter") { vm, receiver, args in
            guard case .dictionary(let d) = receiver, let pred = args.first else { return receiver }
            var result: [String: Value] = [:]
            for (key, value) in d {
                let keep = try vm.invokeValue(pred, args: [.string(key), value])
                if keep.isTruthy { result[key] = value }
            }
            return .dictionary(result)
        }
        register("Dictionary", "merge") { _, receiver, args in
            guard case .dictionary(var d) = receiver, case .dictionary(let other) = args.first else { return receiver }
            d.merge(other) { _, new in new }
            return .dictionary(d)
        }
        register("Dictionary", "forEach") { vm, receiver, args in
            guard case .dictionary(let d) = receiver, let closure = args.first else { return .void }
            for (key, value) in d { _ = try vm.invokeValue(closure, args: [.string(key), value]) }
            return .void
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
