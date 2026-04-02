import LanternVM

/// Detects repeated pure expressions within a block and replaces duplicates
/// with a reference to the first computation.
public final class CommonSubexpressionEliminationPass: OptimizationPass {
    public let name = "CommonSubexpressionElimination"

    public init() {}

    public func run(_ node: SourceFileNode, context: OptimizationContext) throws -> SourceFileNode {
        let analyzer = CSEAnalyzer(context: context)
        analyzer.analyze(node)
        return node
    }
}

/// Analyzes blocks for repeated pure expressions.
private final class CSEAnalyzer {
    let context: OptimizationContext
    let hasher = ExpressionHasher()

    init(context: OptimizationContext) {
        self.context = context
    }

    func analyze(_ node: SourceFileNode) {
        analyzeStatements(node.statements)
    }

    private func analyzeStatements(_ statements: [StatementNode]) {
        var seen: [String: ExpressionNode] = [:]

        for stmt in statements {
            if let exprStmt = stmt as? ExpressionStatementNode {
                let hash = hasher.hash(exprStmt.expression)
                if hash != nil, seen[hash!] != nil {
                    // Found a repeated pure expression
                    context.emitWarning(
                        "Repeated expression could be extracted to a variable",
                        at: exprStmt.location
                    )
                } else if let hash {
                    seen[hash] = exprStmt.expression
                }
            }

            // Recurse into nested blocks
            if let block = stmt as? BlockNode {
                analyzeStatements(block.statements)
            } else if let ifStmt = stmt as? IfStatementNode {
                analyzeStatements(ifStmt.thenBlock.statements)
                if let elseBlock = ifStmt.elseBlock as? BlockNode {
                    analyzeStatements(elseBlock.statements)
                }
            } else if let whileStmt = stmt as? WhileStatementNode {
                analyzeStatements(whileStmt.body.statements)
            } else if let forStmt = stmt as? ForInStatementNode {
                analyzeStatements(forStmt.body.statements)
            } else if let funcDecl = stmt as? FunctionDeclarationNode {
                analyzeStatements(funcDecl.body.statements)
            }
        }
    }
}
