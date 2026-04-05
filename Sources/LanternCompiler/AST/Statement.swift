import LanternVM

// MARK: - Base Statement

/// Base class for all statement nodes.
public class StatementNode: ASTNode {
    public let location: SourceLocation

    public init(location: SourceLocation) {
        self.location = location
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitStatement(self)
    }
}

// MARK: - Block

public final class BlockNode: StatementNode {
    public var statements: [StatementNode]

    public init(statements: [StatementNode], location: SourceLocation) {
        self.statements = statements
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitBlock(self)
    }
}

// MARK: - Variable Declaration

public final class VariableDeclarationNode: StatementNode {
    public let name: String
    public let isMutable: Bool
    public let typeAnnotation: String?
    public var initializer: ExpressionNode?
    public let attributes: [String]
    public let attributeArgs: [String: String]

    public init(name: String, isMutable: Bool, typeAnnotation: String? = nil, initializer: ExpressionNode? = nil, attributes: [String] = [], attributeArgs: [String: String] = [:], location: SourceLocation) {
        self.name = name
        self.isMutable = isMutable
        self.typeAnnotation = typeAnnotation
        self.initializer = initializer
        self.attributes = attributes
        self.attributeArgs = attributeArgs
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitVariableDeclaration(self)
    }
}

// MARK: - Expression Statement

public final class ExpressionStatementNode: StatementNode {
    public var expression: ExpressionNode

    public init(expression: ExpressionNode, location: SourceLocation) {
        self.expression = expression
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitExpressionStatement(self)
    }
}

// MARK: - Control Flow

/// Optional binding used in `if let` / `guard let`.
public struct OptionalBinding {
    public let name: String
    public let isMutable: Bool
    public let value: ExpressionNode

    public init(name: String, isMutable: Bool = false, value: ExpressionNode) {
        self.name = name
        self.isMutable = isMutable
        self.value = value
    }
}

public final class IfStatementNode: StatementNode {
    public let condition: ExpressionNode?
    public let optionalBinding: OptionalBinding?
    public let thenBlock: BlockNode
    public let elseBlock: StatementNode?

    public init(condition: ExpressionNode? = nil, optionalBinding: OptionalBinding? = nil, thenBlock: BlockNode, elseBlock: StatementNode? = nil, location: SourceLocation) {
        self.condition = condition
        self.optionalBinding = optionalBinding
        self.thenBlock = thenBlock
        self.elseBlock = elseBlock
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitIfStatement(self)
    }
}

public final class GuardStatementNode: StatementNode {
    public let condition: ExpressionNode?
    public let optionalBinding: OptionalBinding?
    public let elseBlock: BlockNode

    public init(condition: ExpressionNode? = nil, optionalBinding: OptionalBinding? = nil, elseBlock: BlockNode, location: SourceLocation) {
        self.condition = condition
        self.optionalBinding = optionalBinding
        self.elseBlock = elseBlock
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitGuardStatement(self)
    }
}

public final class WhileStatementNode: StatementNode {
    public let condition: ExpressionNode
    public let body: BlockNode

    public init(condition: ExpressionNode, body: BlockNode, location: SourceLocation) {
        self.condition = condition
        self.body = body
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitWhileStatement(self)
    }
}

public final class ForInStatementNode: StatementNode {
    public let variableName: String
    public let iterable: ExpressionNode
    public let body: BlockNode

    public init(variableName: String, iterable: ExpressionNode, body: BlockNode, location: SourceLocation) {
        self.variableName = variableName
        self.iterable = iterable
        self.body = body
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitForInStatement(self)
    }
}

// MARK: - Jump Statements

public final class ReturnStatementNode: StatementNode {
    public let value: ExpressionNode?

    public init(value: ExpressionNode? = nil, location: SourceLocation) {
        self.value = value
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitReturnStatement(self)
    }
}

public final class BreakStatementNode: StatementNode {
    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitBreakStatement(self)
    }
}

public final class ContinueStatementNode: StatementNode {
    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitContinueStatement(self)
    }
}

// MARK: - Error Handling

public final class ThrowStatementNode: StatementNode {
    public let expression: ExpressionNode

    public init(expression: ExpressionNode, location: SourceLocation) {
        self.expression = expression
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitThrowStatement(self)
    }
}

public struct CatchClause {
    public let pattern: String?
    public let body: BlockNode

    public init(pattern: String? = nil, body: BlockNode) {
        self.pattern = pattern
        self.body = body
    }
}

public final class DoCatchStatementNode: StatementNode {
    public let body: BlockNode
    public let catchClauses: [CatchClause]

    public init(body: BlockNode, catchClauses: [CatchClause], location: SourceLocation) {
        self.body = body
        self.catchClauses = catchClauses
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitDoCatchStatement(self)
    }
}

public final class DeferStatementNode: StatementNode {
    public let body: BlockNode

    public init(body: BlockNode, location: SourceLocation) {
        self.body = body
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitDeferStatement(self)
    }
}

// MARK: - Switch

public enum CasePattern {
    case expression(ExpressionNode)
    case identifier(String)
    case wildcard
    case enumCase(caseName: String, bindings: [String])
    case range(ExpressionNode, ExpressionNode, Bool) // start, end, isClosed
    case binding(String, ExpressionNode?) // `case let x where condition`
    case tuple([CasePattern]) // (.idle, .running) — element-wise matching
}

public struct SwitchCase {
    public let patterns: [CasePattern]
    public let body: BlockNode
    public let isDefault: Bool

    public init(patterns: [CasePattern] = [], body: BlockNode, isDefault: Bool = false) {
        self.patterns = patterns
        self.body = body
        self.isDefault = isDefault
    }
}

public final class SwitchStatementNode: StatementNode {
    public let subject: ExpressionNode
    public let cases: [SwitchCase]

    public init(subject: ExpressionNode, cases: [SwitchCase], location: SourceLocation) {
        self.subject = subject
        self.cases = cases
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitSwitchStatement(self)
    }
}
