import LanternVM

/// Replaces expensive operations with cheaper equivalents (e.g., x*2 -> x<<1).
public final class StrengthReductionPass: OptimizationPass {
    public let name = "StrengthReduction"

    public init() {}

    public func run(_ node: SourceFileNode, context: OptimizationContext) throws -> SourceFileNode {
        let rewriter = StrengthReductionRewriter(context: context)
        _ = try rewriter.visitSourceFile(node)
        return node
    }
}

private final class StrengthReductionRewriter: ASTRewriter {
    let context: OptimizationContext

    init(context: OptimizationContext) {
        self.context = context
    }

    override func visitBinaryExpression(_ node: BinaryExpressionNode) throws -> ASTNode {
        _ = try node.left.accept(self)
        _ = try node.right.accept(self)

        switch node.op {
        case .multiply:
            // x * 2 -> x << 1, x * 4 -> x << 2, x * 8 -> x << 3, etc.
            if let rightInt = node.right as? IntLiteralNode, let shift = log2Exact(rightInt.value) {
                context.markChanged()
                return BinaryExpressionNode(
                    op: .shiftLeft,
                    left: node.left,
                    right: IntLiteralNode(value: shift, location: node.right.location),
                    location: node.location
                )
            }
            // 2 * x -> x << 1
            if let leftInt = node.left as? IntLiteralNode, let shift = log2Exact(leftInt.value) {
                context.markChanged()
                return BinaryExpressionNode(
                    op: .shiftLeft,
                    left: node.right,
                    right: IntLiteralNode(value: shift, location: node.left.location),
                    location: node.location
                )
            }

        case .divide:
            // x / 2 -> x >> 1 (for positive integers only, but we apply it optimistically)
            if let rightInt = node.right as? IntLiteralNode, let shift = log2Exact(rightInt.value) {
                context.markChanged()
                return BinaryExpressionNode(
                    op: .shiftRight,
                    left: node.left,
                    right: IntLiteralNode(value: shift, location: node.right.location),
                    location: node.location
                )
            }

        default:
            break
        }

        return node
    }

    /// Returns the base-2 logarithm if `value` is a power of 2, otherwise nil.
    private func log2Exact(_ value: Int) -> Int? {
        guard value > 0, value & (value - 1) == 0 else { return nil }
        var n = value
        var shift = 0
        while n > 1 {
            n >>= 1
            shift += 1
        }
        return shift
    }
}
