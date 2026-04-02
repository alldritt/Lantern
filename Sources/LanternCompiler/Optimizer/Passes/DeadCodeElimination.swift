import LanternVM

/// Removes unreachable code after return, break, continue, or throw statements.
public final class DeadCodeEliminationPass: OptimizationPass {
    public let name = "DeadCodeElimination"

    public init() {}

    public func run(_ node: SourceFileNode, context: OptimizationContext) throws -> SourceFileNode {
        let rewriter = DeadCodeRewriter(context: context)
        _ = try rewriter.visitSourceFile(node)
        return node
    }
}

private final class DeadCodeRewriter: ASTRewriter {
    let context: OptimizationContext

    init(context: OptimizationContext) {
        self.context = context
    }

    override func visitBlock(_ node: BlockNode) throws -> ASTNode {
        var newStatements: [StatementNode] = []
        var reachable = true

        for stmt in node.statements {
            if !reachable {
                context.markChanged()
                context.emitWarning("Code after return/break/continue/throw will never be executed", at: stmt.location)
                continue
            }

            let result = try stmt.accept(self)
            if let s = result as? StatementNode {
                newStatements.append(s)
            }

            // Check if this statement terminates the block
            if ReachabilityAnalysis.isTerminating(stmt) {
                reachable = false
            }
        }

        node.statements = newStatements
        return node
    }

    override func visitIfStatement(_ node: IfStatementNode) throws -> ASTNode {
        // If condition is a constant bool, eliminate the dead branch
        if let condBool = node.condition as? BoolLiteralNode {
            context.markChanged()
            if condBool.value {
                // Always true: replace with just the then-block
                _ = try node.thenBlock.accept(self)
                return node.thenBlock
            } else {
                // Always false: replace with the else-block or empty
                if let elseBlock = node.elseBlock {
                    _ = try elseBlock.accept(self)
                    return elseBlock
                }
                return BlockNode(statements: [], location: node.location)
            }
        }

        return try super.visitIfStatement(node)
    }

    override func visitWhileStatement(_ node: WhileStatementNode) throws -> ASTNode {
        // while false { ... } is dead code
        if let condBool = node.condition as? BoolLiteralNode, !condBool.value {
            context.markChanged()
            return BlockNode(statements: [], location: node.location)
        }

        return try super.visitWhileStatement(node)
    }
}
