import LanternVM

// MARK: - Base Expression

/// Base class for all expression nodes.
public class ExpressionNode: ASTNode {
    public let location: SourceLocation

    public init(location: SourceLocation) {
        self.location = location
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitExpression(self)
    }
}

// MARK: - Literals

public final class IntLiteralNode: ExpressionNode {
    public let value: Int

    public init(value: Int, location: SourceLocation) {
        self.value = value
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitIntLiteral(self)
    }
}

public final class DoubleLiteralNode: ExpressionNode {
    public let value: Double

    public init(value: Double, location: SourceLocation) {
        self.value = value
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitDoubleLiteral(self)
    }
}

public final class BoolLiteralNode: ExpressionNode {
    public let value: Bool

    public init(value: Bool, location: SourceLocation) {
        self.value = value
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitBoolLiteral(self)
    }
}

public final class StringLiteralNode: ExpressionNode {
    public let value: String

    public init(value: String, location: SourceLocation) {
        self.value = value
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitStringLiteral(self)
    }
}

public final class NilLiteralNode: ExpressionNode {
    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitNilLiteral(self)
    }
}

// MARK: - String Interpolation

public final class StringInterpolationNode: ExpressionNode {
    public let segments: [ExpressionNode]

    public init(segments: [ExpressionNode], location: SourceLocation) {
        self.segments = segments
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitStringInterpolation(self)
    }
}

// MARK: - References

public final class IdentifierNode: ExpressionNode {
    public let name: String

    public init(name: String, location: SourceLocation) {
        self.name = name
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitIdentifier(self)
    }
}

public final class MemberAccessNode: ExpressionNode {
    public let object: ExpressionNode
    public let member: String

    public init(object: ExpressionNode, member: String, location: SourceLocation) {
        self.object = object
        self.member = member
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitMemberAccess(self)
    }
}

public final class SelfNode: ExpressionNode {
    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitSelf(self)
    }
}

public final class TypeReferenceNode: ExpressionNode {
    public let typeName: String

    public init(typeName: String, location: SourceLocation) {
        self.typeName = typeName
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitTypeReference(self)
    }
}

// MARK: - Operators

public enum BinaryOperator: String, Sendable {
    case add = "+"
    case subtract = "-"
    case multiply = "*"
    case divide = "/"
    case modulo = "%"
    case equal = "=="
    case notEqual = "!="
    case lessThan = "<"
    case greaterThan = ">"
    case lessThanOrEqual = "<="
    case greaterThanOrEqual = ">="
    case and = "&&"
    case or = "||"
    case closedRange = "..."
    case halfOpenRange = "..<"
    case nilCoalescing = "??"
    case shiftLeft = "<<"
    case shiftRight = ">>"
    case bitwiseAnd = "&"
    case bitwiseOr = "|"
    case bitwiseXor = "^"
}

public enum UnaryOperator: String, Sendable {
    case negate = "-"
    case not = "!"
    case bitwiseNot = "~"
}

public final class BinaryExpressionNode: ExpressionNode {
    public let op: BinaryOperator
    public let left: ExpressionNode
    public let right: ExpressionNode

    public init(op: BinaryOperator, left: ExpressionNode, right: ExpressionNode, location: SourceLocation) {
        self.op = op
        self.left = left
        self.right = right
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitBinaryExpression(self)
    }
}

public final class UnaryExpressionNode: ExpressionNode {
    public let op: UnaryOperator
    public let operand: ExpressionNode

    public init(op: UnaryOperator, operand: ExpressionNode, location: SourceLocation) {
        self.op = op
        self.operand = operand
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitUnaryExpression(self)
    }
}

// MARK: - Calls and Subscripts

public final class FunctionCallNode: ExpressionNode {
    public let callee: ExpressionNode
    public let arguments: [Argument]

    public struct Argument {
        public let label: String?
        public let value: ExpressionNode

        public init(label: String? = nil, value: ExpressionNode) {
            self.label = label
            self.value = value
        }
    }

    public init(callee: ExpressionNode, arguments: [Argument], location: SourceLocation) {
        self.callee = callee
        self.arguments = arguments
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitFunctionCall(self)
    }
}

public final class SubscriptNode: ExpressionNode {
    public let object: ExpressionNode
    public let index: ExpressionNode

    public init(object: ExpressionNode, index: ExpressionNode, location: SourceLocation) {
        self.object = object
        self.index = index
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitSubscript(self)
    }
}

// MARK: - Collection Literals

public final class ArrayLiteralNode: ExpressionNode {
    public let elements: [ExpressionNode]

    public init(elements: [ExpressionNode], location: SourceLocation) {
        self.elements = elements
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitArrayLiteral(self)
    }
}

public final class DictionaryLiteralNode: ExpressionNode {
    public let entries: [(key: ExpressionNode, value: ExpressionNode)]

    public init(entries: [(key: ExpressionNode, value: ExpressionNode)], location: SourceLocation) {
        self.entries = entries
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitDictionaryLiteral(self)
    }
}

// MARK: - Closures

public final class ClosureExpressionNode: ExpressionNode {
    public let parameters: [String]
    public let body: BlockNode

    public init(parameters: [String], body: BlockNode, location: SourceLocation) {
        self.parameters = parameters
        self.body = body
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitClosureExpression(self)
    }
}

// MARK: - Optionals

public final class ForceUnwrapNode: ExpressionNode {
    public let expression: ExpressionNode

    public init(expression: ExpressionNode, location: SourceLocation) {
        self.expression = expression
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitForceUnwrap(self)
    }
}

public final class OptionalChainingNode: ExpressionNode {
    public let expression: ExpressionNode

    public init(expression: ExpressionNode, location: SourceLocation) {
        self.expression = expression
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitOptionalChaining(self)
    }
}

// MARK: - Try / Await

public enum TryKind: Sendable {
    case `try`
    case tryOptional  // try?
    case tryForce     // try!
}

public final class TryExpressionNode: ExpressionNode {
    public let kind: TryKind
    public let expression: ExpressionNode

    public init(kind: TryKind, expression: ExpressionNode, location: SourceLocation) {
        self.kind = kind
        self.expression = expression
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitTryExpression(self)
    }
}

public final class AwaitExpressionNode: ExpressionNode {
    public let expression: ExpressionNode

    public init(expression: ExpressionNode, location: SourceLocation) {
        self.expression = expression
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitAwaitExpression(self)
    }
}

// MARK: - Assignment and Ternary

public final class AssignmentNode: ExpressionNode {
    public let target: ExpressionNode
    public let value: ExpressionNode

    public init(target: ExpressionNode, value: ExpressionNode, location: SourceLocation) {
        self.target = target
        self.value = value
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitAssignment(self)
    }
}

public final class TernaryExpressionNode: ExpressionNode {
    public let condition: ExpressionNode
    public let thenExpr: ExpressionNode
    public let elseExpr: ExpressionNode

    public init(condition: ExpressionNode, thenExpr: ExpressionNode, elseExpr: ExpressionNode, location: SourceLocation) {
        self.condition = condition
        self.thenExpr = thenExpr
        self.elseExpr = elseExpr
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitTernaryExpression(self)
    }
}
