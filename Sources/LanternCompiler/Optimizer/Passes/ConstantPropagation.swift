import LanternVM

/// Tracks `let` bindings with known constant values and replaces references.
public final class ConstantPropagationPass: OptimizationPass {
    public let name = "ConstantPropagation"

    public init() {}

    public func run(_ node: SourceFileNode, context: OptimizationContext) throws -> SourceFileNode {
        // First pass: collect let bindings with literal initializers
        let tracker = ConstantTracker()
        tracker.scan(node)

        for (name, value) in tracker.constants {
            context.constants[name] = value
        }

        // Second pass: replace identifier references with their constant values
        let rewriter = PropagationRewriter(constants: context.constants, context: context)
        _ = try rewriter.visitSourceFile(node)
        return node
    }
}

private final class PropagationRewriter: ASTRewriter {
    let constants: [String: ConstantValue]
    let context: OptimizationContext

    init(constants: [String: ConstantValue], context: OptimizationContext) {
        self.constants = constants
        self.context = context
    }

    override func visitIdentifier(_ node: IdentifierNode) throws -> ASTNode {
        guard let value = constants[node.name] else { return node }

        context.markChanged()
        switch value {
        case .int(let v): return IntLiteralNode(value: v, location: node.location)
        case .double(let v): return DoubleLiteralNode(value: v, location: node.location)
        case .bool(let v): return BoolLiteralNode(value: v, location: node.location)
        case .string(let v): return StringLiteralNode(value: v, location: node.location)
        case .nil_: return NilLiteralNode(location: node.location)
        }
    }
}
