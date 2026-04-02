import LanternVM

/// Scans the AST for `let` bindings with literal initializers and tracks their constant values.
public final class ConstantTracker {
    public private(set) var constants: [String: ConstantValue] = [:]
    private var mutatedNames: Set<String> = []

    public init() {}

    /// Scan the AST and collect constant bindings.
    public func scan(_ node: SourceFileNode) {
        for stmt in node.statements {
            scanStatement(stmt)
        }
        // Remove any names that were later mutated
        for name in mutatedNames {
            constants.removeValue(forKey: name)
        }
    }

    private func scanStatement(_ stmt: StatementNode) {
        if let varDecl = stmt as? VariableDeclarationNode {
            if !varDecl.isMutable, let initializer = varDecl.initializer {
                if let value = extractConstant(initializer) {
                    constants[varDecl.name] = value
                }
            }
            if varDecl.isMutable {
                mutatedNames.insert(varDecl.name)
            }
        } else if let block = stmt as? BlockNode {
            for s in block.statements { scanStatement(s) }
        } else if let ifStmt = stmt as? IfStatementNode {
            for s in ifStmt.thenBlock.statements { scanStatement(s) }
            if let elseBlock = ifStmt.elseBlock {
                scanStatement(elseBlock)
            }
        } else if let whileStmt = stmt as? WhileStatementNode {
            for s in whileStmt.body.statements { scanStatement(s) }
        } else if let forStmt = stmt as? ForInStatementNode {
            for s in forStmt.body.statements { scanStatement(s) }
        } else if let funcDecl = stmt as? FunctionDeclarationNode {
            for s in funcDecl.body.statements { scanStatement(s) }
        } else if let exprStmt = stmt as? ExpressionStatementNode {
            // Track mutations through assignment
            if let assign = exprStmt.expression as? AssignmentNode,
               let ident = assign.target as? IdentifierNode {
                mutatedNames.insert(ident.name)
            }
        }
    }

    private func extractConstant(_ expr: ExpressionNode) -> ConstantValue? {
        if let intLit = expr as? IntLiteralNode { return .int(intLit.value) }
        if let doubleLit = expr as? DoubleLiteralNode { return .double(doubleLit.value) }
        if let boolLit = expr as? BoolLiteralNode { return .bool(boolLit.value) }
        if let stringLit = expr as? StringLiteralNode { return .string(stringLit.value) }
        if expr is NilLiteralNode { return .nil_ }
        return nil
    }
}
