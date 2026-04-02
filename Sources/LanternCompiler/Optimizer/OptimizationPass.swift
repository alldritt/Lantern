import LanternVM

/// Protocol that all optimization passes conform to.
public protocol OptimizationPass {
    /// A human-readable name for this pass.
    var name: String { get }

    /// Run the pass on the given source file AST, potentially modifying it.
    /// Returns the (possibly transformed) AST node.
    func run(_ node: SourceFileNode, context: OptimizationContext) throws -> SourceFileNode
}
