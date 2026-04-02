import LanternVM

/// Visitor pattern protocol for AST traversal.
public protocol ASTVisitor {
    associatedtype Result

    // Source file
    func visitSourceFile(_ node: SourceFileNode) throws -> Result

    // Expressions
    func visitExpression(_ node: ExpressionNode) throws -> Result
    func visitIntLiteral(_ node: IntLiteralNode) throws -> Result
    func visitDoubleLiteral(_ node: DoubleLiteralNode) throws -> Result
    func visitBoolLiteral(_ node: BoolLiteralNode) throws -> Result
    func visitStringLiteral(_ node: StringLiteralNode) throws -> Result
    func visitNilLiteral(_ node: NilLiteralNode) throws -> Result
    func visitStringInterpolation(_ node: StringInterpolationNode) throws -> Result
    func visitIdentifier(_ node: IdentifierNode) throws -> Result
    func visitMemberAccess(_ node: MemberAccessNode) throws -> Result
    func visitSelf(_ node: SelfNode) throws -> Result
    func visitTypeReference(_ node: TypeReferenceNode) throws -> Result
    func visitBinaryExpression(_ node: BinaryExpressionNode) throws -> Result
    func visitUnaryExpression(_ node: UnaryExpressionNode) throws -> Result
    func visitFunctionCall(_ node: FunctionCallNode) throws -> Result
    func visitSubscript(_ node: SubscriptNode) throws -> Result
    func visitArrayLiteral(_ node: ArrayLiteralNode) throws -> Result
    func visitDictionaryLiteral(_ node: DictionaryLiteralNode) throws -> Result
    func visitClosureExpression(_ node: ClosureExpressionNode) throws -> Result
    func visitForceUnwrap(_ node: ForceUnwrapNode) throws -> Result
    func visitOptionalChaining(_ node: OptionalChainingNode) throws -> Result
    func visitTryExpression(_ node: TryExpressionNode) throws -> Result
    func visitAwaitExpression(_ node: AwaitExpressionNode) throws -> Result
    func visitAssignment(_ node: AssignmentNode) throws -> Result
    func visitTernaryExpression(_ node: TernaryExpressionNode) throws -> Result

    // Statements
    func visitStatement(_ node: StatementNode) throws -> Result
    func visitBlock(_ node: BlockNode) throws -> Result
    func visitVariableDeclaration(_ node: VariableDeclarationNode) throws -> Result
    func visitExpressionStatement(_ node: ExpressionStatementNode) throws -> Result
    func visitIfStatement(_ node: IfStatementNode) throws -> Result
    func visitGuardStatement(_ node: GuardStatementNode) throws -> Result
    func visitWhileStatement(_ node: WhileStatementNode) throws -> Result
    func visitForInStatement(_ node: ForInStatementNode) throws -> Result
    func visitReturnStatement(_ node: ReturnStatementNode) throws -> Result
    func visitBreakStatement(_ node: BreakStatementNode) throws -> Result
    func visitContinueStatement(_ node: ContinueStatementNode) throws -> Result
    func visitThrowStatement(_ node: ThrowStatementNode) throws -> Result
    func visitDoCatchStatement(_ node: DoCatchStatementNode) throws -> Result
    func visitDeferStatement(_ node: DeferStatementNode) throws -> Result
    func visitSwitchStatement(_ node: SwitchStatementNode) throws -> Result

    // Declarations
    func visitDeclaration(_ node: DeclarationNode) throws -> Result
    func visitFunctionDeclaration(_ node: FunctionDeclarationNode) throws -> Result
    func visitStructDeclaration(_ node: StructDeclarationNode) throws -> Result
    func visitClassDeclaration(_ node: ClassDeclarationNode) throws -> Result
    func visitEnumDeclaration(_ node: EnumDeclarationNode) throws -> Result
    func visitEnumCase(_ node: EnumCaseNode) throws -> Result
    func visitProtocolDeclaration(_ node: ProtocolDeclarationNode) throws -> Result
    func visitPropertyRequirement(_ node: PropertyRequirementNode) throws -> Result
    func visitExtension(_ node: ExtensionNode) throws -> Result
    func visitProperty(_ node: PropertyNode) throws -> Result
    func visitComputedProperty(_ node: ComputedPropertyNode) throws -> Result
    func visitInitializer(_ node: InitializerNode) throws -> Result
}

// MARK: - AST Rewriter

/// An open class with default pass-through implementations of every visit method.
/// Subclass and override specific methods to transform the AST.
open class ASTRewriter: ASTVisitor {
    public typealias Result = ASTNode

    public init() {}

    // MARK: - Source File

    open func visitSourceFile(_ node: SourceFileNode) throws -> ASTNode {
        var newStatements: [StatementNode] = []
        for stmt in node.statements {
            let result = try stmt.accept(self)
            if let s = result as? StatementNode {
                newStatements.append(s)
            }
        }
        node.statements = newStatements
        return node
    }

    // MARK: - Expressions

    open func visitExpression(_ node: ExpressionNode) throws -> ASTNode { node }

    open func visitIntLiteral(_ node: IntLiteralNode) throws -> ASTNode { node }
    open func visitDoubleLiteral(_ node: DoubleLiteralNode) throws -> ASTNode { node }
    open func visitBoolLiteral(_ node: BoolLiteralNode) throws -> ASTNode { node }
    open func visitStringLiteral(_ node: StringLiteralNode) throws -> ASTNode { node }
    open func visitNilLiteral(_ node: NilLiteralNode) throws -> ASTNode { node }
    open func visitStringInterpolation(_ node: StringInterpolationNode) throws -> ASTNode { node }
    open func visitIdentifier(_ node: IdentifierNode) throws -> ASTNode { node }

    open func visitMemberAccess(_ node: MemberAccessNode) throws -> ASTNode {
        _ = try node.object.accept(self)
        return node
    }

    open func visitSelf(_ node: SelfNode) throws -> ASTNode { node }
    open func visitTypeReference(_ node: TypeReferenceNode) throws -> ASTNode { node }

    open func visitBinaryExpression(_ node: BinaryExpressionNode) throws -> ASTNode {
        _ = try node.left.accept(self)
        _ = try node.right.accept(self)
        return node
    }

    open func visitUnaryExpression(_ node: UnaryExpressionNode) throws -> ASTNode {
        _ = try node.operand.accept(self)
        return node
    }

    open func visitFunctionCall(_ node: FunctionCallNode) throws -> ASTNode {
        _ = try node.callee.accept(self)
        for arg in node.arguments {
            _ = try arg.value.accept(self)
        }
        return node
    }

    open func visitSubscript(_ node: SubscriptNode) throws -> ASTNode {
        _ = try node.object.accept(self)
        _ = try node.index.accept(self)
        return node
    }

    open func visitArrayLiteral(_ node: ArrayLiteralNode) throws -> ASTNode {
        for el in node.elements { _ = try el.accept(self) }
        return node
    }

    open func visitDictionaryLiteral(_ node: DictionaryLiteralNode) throws -> ASTNode {
        for entry in node.entries {
            _ = try entry.key.accept(self)
            _ = try entry.value.accept(self)
        }
        return node
    }

    open func visitClosureExpression(_ node: ClosureExpressionNode) throws -> ASTNode {
        _ = try node.body.accept(self)
        return node
    }

    open func visitForceUnwrap(_ node: ForceUnwrapNode) throws -> ASTNode {
        _ = try node.expression.accept(self)
        return node
    }

    open func visitOptionalChaining(_ node: OptionalChainingNode) throws -> ASTNode {
        _ = try node.expression.accept(self)
        return node
    }

    open func visitTryExpression(_ node: TryExpressionNode) throws -> ASTNode {
        _ = try node.expression.accept(self)
        return node
    }

    open func visitAwaitExpression(_ node: AwaitExpressionNode) throws -> ASTNode {
        _ = try node.expression.accept(self)
        return node
    }

    open func visitAssignment(_ node: AssignmentNode) throws -> ASTNode {
        _ = try node.target.accept(self)
        _ = try node.value.accept(self)
        return node
    }

    open func visitTernaryExpression(_ node: TernaryExpressionNode) throws -> ASTNode {
        _ = try node.condition.accept(self)
        _ = try node.thenExpr.accept(self)
        _ = try node.elseExpr.accept(self)
        return node
    }

    // MARK: - Statements

    open func visitStatement(_ node: StatementNode) throws -> ASTNode { node }

    open func visitBlock(_ node: BlockNode) throws -> ASTNode {
        var newStatements: [StatementNode] = []
        for stmt in node.statements {
            let result = try stmt.accept(self)
            if let s = result as? StatementNode {
                newStatements.append(s)
            }
        }
        node.statements = newStatements
        return node
    }

    open func visitVariableDeclaration(_ node: VariableDeclarationNode) throws -> ASTNode {
        if let init_ = node.initializer, let rewritten = try init_.accept(self) as? ExpressionNode {
            node.initializer = rewritten
        }
        return node
    }

    open func visitExpressionStatement(_ node: ExpressionStatementNode) throws -> ASTNode {
        if let rewritten = try node.expression.accept(self) as? ExpressionNode {
            node.expression = rewritten
        }
        return node
    }

    open func visitIfStatement(_ node: IfStatementNode) throws -> ASTNode {
        if let cond = node.condition { _ = try cond.accept(self) }
        if let binding = node.optionalBinding { _ = try binding.value.accept(self) }
        _ = try node.thenBlock.accept(self)
        if let elseBlock = node.elseBlock { _ = try elseBlock.accept(self) }
        return node
    }

    open func visitGuardStatement(_ node: GuardStatementNode) throws -> ASTNode {
        if let cond = node.condition { _ = try cond.accept(self) }
        if let binding = node.optionalBinding { _ = try binding.value.accept(self) }
        _ = try node.elseBlock.accept(self)
        return node
    }

    open func visitWhileStatement(_ node: WhileStatementNode) throws -> ASTNode {
        _ = try node.condition.accept(self)
        _ = try node.body.accept(self)
        return node
    }

    open func visitForInStatement(_ node: ForInStatementNode) throws -> ASTNode {
        _ = try node.iterable.accept(self)
        _ = try node.body.accept(self)
        return node
    }

    open func visitReturnStatement(_ node: ReturnStatementNode) throws -> ASTNode {
        if let val = node.value { _ = try val.accept(self) }
        return node
    }

    open func visitBreakStatement(_ node: BreakStatementNode) throws -> ASTNode { node }
    open func visitContinueStatement(_ node: ContinueStatementNode) throws -> ASTNode { node }

    open func visitThrowStatement(_ node: ThrowStatementNode) throws -> ASTNode {
        _ = try node.expression.accept(self)
        return node
    }

    open func visitDoCatchStatement(_ node: DoCatchStatementNode) throws -> ASTNode {
        _ = try node.body.accept(self)
        for clause in node.catchClauses {
            _ = try clause.body.accept(self)
        }
        return node
    }

    open func visitDeferStatement(_ node: DeferStatementNode) throws -> ASTNode {
        _ = try node.body.accept(self)
        return node
    }

    open func visitSwitchStatement(_ node: SwitchStatementNode) throws -> ASTNode {
        _ = try node.subject.accept(self)
        for c in node.cases {
            _ = try c.body.accept(self)
        }
        return node
    }

    // MARK: - Declarations

    open func visitDeclaration(_ node: DeclarationNode) throws -> ASTNode { node }

    open func visitFunctionDeclaration(_ node: FunctionDeclarationNode) throws -> ASTNode {
        _ = try node.body.accept(self)
        return node
    }

    open func visitStructDeclaration(_ node: StructDeclarationNode) throws -> ASTNode {
        var newMembers: [StatementNode] = []
        for member in node.members {
            let result = try member.accept(self)
            if let s = result as? StatementNode {
                newMembers.append(s)
            }
        }
        node.members = newMembers
        return node
    }

    open func visitClassDeclaration(_ node: ClassDeclarationNode) throws -> ASTNode {
        var newMembers: [StatementNode] = []
        for member in node.members {
            let result = try member.accept(self)
            if let s = result as? StatementNode {
                newMembers.append(s)
            }
        }
        node.members = newMembers
        return node
    }

    open func visitEnumDeclaration(_ node: EnumDeclarationNode) throws -> ASTNode {
        for c in node.cases { _ = try c.accept(self) }
        return node
    }

    open func visitEnumCase(_ node: EnumCaseNode) throws -> ASTNode { node }

    open func visitProtocolDeclaration(_ node: ProtocolDeclarationNode) throws -> ASTNode {
        var newReqs: [StatementNode] = []
        for req in node.requirements {
            let result = try req.accept(self)
            if let s = result as? StatementNode {
                newReqs.append(s)
            }
        }
        node.requirements = newReqs
        return node
    }

    open func visitPropertyRequirement(_ node: PropertyRequirementNode) throws -> ASTNode { node }

    open func visitExtension(_ node: ExtensionNode) throws -> ASTNode {
        var newMembers: [StatementNode] = []
        for member in node.members {
            let result = try member.accept(self)
            if let s = result as? StatementNode {
                newMembers.append(s)
            }
        }
        node.members = newMembers
        return node
    }

    open func visitProperty(_ node: PropertyNode) throws -> ASTNode {
        if let init_ = node.initializer { _ = try init_.accept(self) }
        return node
    }

    open func visitComputedProperty(_ node: ComputedPropertyNode) throws -> ASTNode {
        _ = try node.getter.accept(self)
        if let setter = node.setter { _ = try setter.accept(self) }
        return node
    }

    open func visitInitializer(_ node: InitializerNode) throws -> ASTNode {
        _ = try node.body.accept(self)
        return node
    }
}
