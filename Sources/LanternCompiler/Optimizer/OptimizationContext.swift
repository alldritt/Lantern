import LanternVM

/// A compile-time constant value used during optimization.
public enum ConstantValue: Sendable, Equatable {
    case int(Int)
    case double(Double)
    case bool(Bool)
    case string(String)
    case nil_
}

/// Shared state available to all optimization passes.
public final class OptimizationContext: @unchecked Sendable {
    /// Known constant bindings (let variable name -> value).
    public var constants: [String: ConstantValue] = [:]

    /// Names of functions known to be pure (no side effects).
    public var pureFunctions: Set<String> = []

    /// Whether any changes were made during the current pass.
    public var changed: Bool = false

    /// Diagnostics emitted during optimization.
    public var diagnostics: [CompilerDiagnostic] = []

    public init() {}

    public func reset() {
        changed = false
    }

    public func markChanged() {
        changed = true
    }

    public func emitWarning(_ message: String, at location: SourceLocation? = nil) {
        diagnostics.append(CompilerDiagnostic(message: message, location: location, severity: .warning))
    }
}
