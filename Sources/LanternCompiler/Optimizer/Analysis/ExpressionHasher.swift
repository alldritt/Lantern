import LanternVM

/// Produces a deterministic string hash for pure expressions,
/// used by the common subexpression elimination pass.
public final class ExpressionHasher {
    public init() {}

    /// Returns a hash string for a pure expression, or nil if the expression has side effects.
    public func hash(_ expr: ExpressionNode) -> String? {
        switch expr {
        case let intLit as IntLiteralNode:
            return "int(\(intLit.value))"
        case let doubleLit as DoubleLiteralNode:
            return "double(\(doubleLit.value))"
        case let boolLit as BoolLiteralNode:
            return "bool(\(boolLit.value))"
        case let stringLit as StringLiteralNode:
            return "string(\(stringLit.value))"
        case is NilLiteralNode:
            return "nil"
        case let ident as IdentifierNode:
            return "id(\(ident.name))"
        case let binary as BinaryExpressionNode:
            guard let leftHash = hash(binary.left),
                  let rightHash = hash(binary.right) else { return nil }
            return "binary(\(binary.op.rawValue),\(leftHash),\(rightHash))"
        case let unary as UnaryExpressionNode:
            guard let operandHash = hash(unary.operand) else { return nil }
            return "unary(\(unary.op.rawValue),\(operandHash))"
        case let member as MemberAccessNode:
            guard let objHash = hash(member.object) else { return nil }
            return "member(\(objHash),\(member.member))"
        case let sub as SubscriptNode:
            guard let objHash = hash(sub.object),
                  let indexHash = hash(sub.index) else { return nil }
            return "subscript(\(objHash),\(indexHash))"
        case let array as ArrayLiteralNode:
            var parts: [String] = []
            for el in array.elements {
                guard let h = hash(el) else { return nil }
                parts.append(h)
            }
            return "array(\(parts.joined(separator: ",")))"
        default:
            // Expressions with potential side effects (calls, assignments, etc.) are not pure
            return nil
        }
    }
}
