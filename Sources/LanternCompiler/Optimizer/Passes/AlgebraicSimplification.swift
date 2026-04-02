import LanternVM

/// Simplifies algebraic identities: x+0 -> x, x*1 -> x, x*0 -> 0, etc.
public final class AlgebraicSimplificationPass: OptimizationPass {
    public let name = "AlgebraicSimplification"

    public init() {}

    public func run(_ node: SourceFileNode, context: OptimizationContext) throws -> SourceFileNode {
        let rewriter = AlgebraicRewriter(context: context)
        _ = try rewriter.visitSourceFile(node)
        return node
    }
}

private final class AlgebraicRewriter: ASTRewriter {
    let context: OptimizationContext

    init(context: OptimizationContext) {
        self.context = context
    }

    override func visitBinaryExpression(_ node: BinaryExpressionNode) throws -> ASTNode {
        _ = try node.left.accept(self)
        _ = try node.right.accept(self)

        let leftIsZero = isIntLiteral(node.left, value: 0)
        let rightIsZero = isIntLiteral(node.right, value: 0)
        let leftIsOne = isIntLiteral(node.left, value: 1)
        let rightIsOne = isIntLiteral(node.right, value: 1)

        switch node.op {
        // x + 0 -> x, 0 + x -> x
        case .add:
            if rightIsZero { context.markChanged(); return node.left }
            if leftIsZero { context.markChanged(); return node.right }

        // x - 0 -> x
        case .subtract:
            if rightIsZero { context.markChanged(); return node.left }

        // x * 1 -> x, 1 * x -> x
        // x * 0 -> 0, 0 * x -> 0
        case .multiply:
            if rightIsOne { context.markChanged(); return node.left }
            if leftIsOne { context.markChanged(); return node.right }
            if rightIsZero { context.markChanged(); return IntLiteralNode(value: 0, location: node.location) }
            if leftIsZero { context.markChanged(); return IntLiteralNode(value: 0, location: node.location) }

        // x / 1 -> x
        case .divide:
            if rightIsOne { context.markChanged(); return node.left }

        // x && true -> x, true && x -> x
        // x && false -> false
        case .and:
            if isBoolLiteral(node.right, value: true) { context.markChanged(); return node.left }
            if isBoolLiteral(node.left, value: true) { context.markChanged(); return node.right }
            if isBoolLiteral(node.right, value: false) || isBoolLiteral(node.left, value: false) {
                context.markChanged()
                return BoolLiteralNode(value: false, location: node.location)
            }

        // x || false -> x, false || x -> x
        // x || true -> true
        case .or:
            if isBoolLiteral(node.right, value: false) { context.markChanged(); return node.left }
            if isBoolLiteral(node.left, value: false) { context.markChanged(); return node.right }
            if isBoolLiteral(node.right, value: true) || isBoolLiteral(node.left, value: true) {
                context.markChanged()
                return BoolLiteralNode(value: true, location: node.location)
            }

        default:
            break
        }

        return node
    }

    override func visitUnaryExpression(_ node: UnaryExpressionNode) throws -> ASTNode {
        _ = try node.operand.accept(self)

        // !!x -> x
        if node.op == .not, let inner = node.operand as? UnaryExpressionNode, inner.op == .not {
            context.markChanged()
            return inner.operand
        }

        // --x -> x (integer)
        if node.op == .negate, let inner = node.operand as? UnaryExpressionNode, inner.op == .negate {
            context.markChanged()
            return inner.operand
        }

        return node
    }

    private func isIntLiteral(_ node: ExpressionNode, value: Int) -> Bool {
        (node as? IntLiteralNode)?.value == value
    }

    private func isBoolLiteral(_ node: ExpressionNode, value: Bool) -> Bool {
        (node as? BoolLiteralNode)?.value == value
    }
}
