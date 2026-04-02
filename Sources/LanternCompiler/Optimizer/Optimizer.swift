import LanternVM

/// Manages and runs optimization passes on the AST.
public final class Optimizer: @unchecked Sendable {
    private var passes: [OptimizationPass]
    private let context: OptimizationContext
    private let maxIterations: Int

    /// The default set of optimization passes.
    public static var defaultPasses: [OptimizationPass] {
        [
            ConstantFoldingPass(),
            ConstantPropagationPass(),
            AlgebraicSimplificationPass(),
            StrengthReductionPass(),
            CommonSubexpressionEliminationPass(),
            DeadCodeEliminationPass(),
        ]
    }

    public init(passes: [OptimizationPass]? = nil, maxIterations: Int = 3) {
        self.passes = passes ?? Self.defaultPasses
        self.context = OptimizationContext()
        self.maxIterations = maxIterations
    }

    /// Run all passes on the AST, iterating until no more changes are made.
    public func optimize(_ ast: SourceFileNode) throws -> SourceFileNode {
        var current = ast

        for _ in 0..<maxIterations {
            context.reset()

            for pass in passes {
                current = try pass.run(current, context: context)
            }

            if !context.changed {
                break
            }
        }

        return current
    }

    /// Any diagnostics emitted during optimization.
    public var diagnostics: [CompilerDiagnostic] {
        context.diagnostics
    }
}
