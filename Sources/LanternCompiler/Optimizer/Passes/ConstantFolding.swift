import LanternVM

/// Folds compile-time constant expressions into literal values.
public final class ConstantFoldingPass: OptimizationPass {
    public let name = "ConstantFolding"

    public init() {}

    public func run(_ node: SourceFileNode, context: OptimizationContext) throws -> SourceFileNode {
        let rewriter = ConstantFoldingRewriter(context: context)
        if let result = try rewriter.visitSourceFile(node) as? SourceFileNode {
            return result
        }
        return node
    }
}

private final class ConstantFoldingRewriter: ASTRewriter {
    let context: OptimizationContext

    init(context: OptimizationContext) {
        self.context = context
    }

    override func visitBinaryExpression(_ node: BinaryExpressionNode) throws -> ASTNode {
        // First, recurse into children
        _ = try node.left.accept(self)
        _ = try node.right.accept(self)

        // Try to fold two integer literals
        if let leftInt = node.left as? IntLiteralNode,
           let rightInt = node.right as? IntLiteralNode {
            if let result = foldIntBinary(node.op, leftInt.value, rightInt.value) {
                context.markChanged()
                return result
            }
        }

        // Try to fold two double literals
        if let leftDouble = asDouble(node.left),
           let rightDouble = asDouble(node.right),
           (node.left is DoubleLiteralNode || node.right is DoubleLiteralNode) {
            if let result = foldDoubleBinary(node.op, leftDouble, rightDouble, location: node.location) {
                context.markChanged()
                return result
            }
        }

        // Try to fold two bool literals
        if let leftBool = node.left as? BoolLiteralNode,
           let rightBool = node.right as? BoolLiteralNode {
            if let result = foldBoolBinary(node.op, leftBool.value, rightBool.value, location: node.location) {
                context.markChanged()
                return result
            }
        }

        // Try to fold string concatenation
        if node.op == .add,
           let leftStr = node.left as? StringLiteralNode,
           let rightStr = node.right as? StringLiteralNode {
            context.markChanged()
            return StringLiteralNode(value: leftStr.value + rightStr.value, location: node.location)
        }

        return node
    }

    override func visitUnaryExpression(_ node: UnaryExpressionNode) throws -> ASTNode {
        _ = try node.operand.accept(self)

        if let intLit = node.operand as? IntLiteralNode, node.op == .negate {
            context.markChanged()
            return IntLiteralNode(value: -intLit.value, location: node.location)
        }
        if let doubleLit = node.operand as? DoubleLiteralNode, node.op == .negate {
            context.markChanged()
            return DoubleLiteralNode(value: -doubleLit.value, location: node.location)
        }
        if let boolLit = node.operand as? BoolLiteralNode, node.op == .not {
            context.markChanged()
            return BoolLiteralNode(value: !boolLit.value, location: node.location)
        }

        return node
    }

    // MARK: - Folding Helpers

    private func foldIntBinary(_ op: BinaryOperator, _ left: Int, _ right: Int) -> ASTNode? {
        let loc = SourceLocation.unknown
        switch op {
        case .add: return IntLiteralNode(value: left + right, location: loc)
        case .subtract: return IntLiteralNode(value: left - right, location: loc)
        case .multiply: return IntLiteralNode(value: left * right, location: loc)
        case .divide where right != 0: return IntLiteralNode(value: left / right, location: loc)
        case .modulo where right != 0: return IntLiteralNode(value: left % right, location: loc)
        case .equal: return BoolLiteralNode(value: left == right, location: loc)
        case .notEqual: return BoolLiteralNode(value: left != right, location: loc)
        case .lessThan: return BoolLiteralNode(value: left < right, location: loc)
        case .greaterThan: return BoolLiteralNode(value: left > right, location: loc)
        case .lessThanOrEqual: return BoolLiteralNode(value: left <= right, location: loc)
        case .greaterThanOrEqual: return BoolLiteralNode(value: left >= right, location: loc)
        case .shiftLeft: return IntLiteralNode(value: left << right, location: loc)
        case .shiftRight: return IntLiteralNode(value: left >> right, location: loc)
        case .bitwiseAnd: return IntLiteralNode(value: left & right, location: loc)
        case .bitwiseOr: return IntLiteralNode(value: left | right, location: loc)
        case .bitwiseXor: return IntLiteralNode(value: left ^ right, location: loc)
        default: return nil
        }
    }

    private func foldDoubleBinary(_ op: BinaryOperator, _ left: Double, _ right: Double, location: SourceLocation) -> ASTNode? {
        switch op {
        case .add: return DoubleLiteralNode(value: left + right, location: location)
        case .subtract: return DoubleLiteralNode(value: left - right, location: location)
        case .multiply: return DoubleLiteralNode(value: left * right, location: location)
        case .divide where right != 0: return DoubleLiteralNode(value: left / right, location: location)
        case .equal: return BoolLiteralNode(value: left == right, location: location)
        case .notEqual: return BoolLiteralNode(value: left != right, location: location)
        case .lessThan: return BoolLiteralNode(value: left < right, location: location)
        case .greaterThan: return BoolLiteralNode(value: left > right, location: location)
        case .lessThanOrEqual: return BoolLiteralNode(value: left <= right, location: location)
        case .greaterThanOrEqual: return BoolLiteralNode(value: left >= right, location: location)
        default: return nil
        }
    }

    private func foldBoolBinary(_ op: BinaryOperator, _ left: Bool, _ right: Bool, location: SourceLocation) -> ASTNode? {
        switch op {
        case .and: return BoolLiteralNode(value: left && right, location: location)
        case .or: return BoolLiteralNode(value: left || right, location: location)
        case .equal: return BoolLiteralNode(value: left == right, location: location)
        case .notEqual: return BoolLiteralNode(value: left != right, location: location)
        default: return nil
        }
    }

    private func asDouble(_ expr: ExpressionNode) -> Double? {
        if let d = expr as? DoubleLiteralNode { return d.value }
        if let i = expr as? IntLiteralNode { return Double(i.value) }
        return nil
    }
}
