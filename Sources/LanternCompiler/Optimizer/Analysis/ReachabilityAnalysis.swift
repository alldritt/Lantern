import LanternVM

/// Utility for determining whether a statement terminates control flow.
public enum ReachabilityAnalysis {
    /// Returns true if the given statement always terminates (return, break, continue, throw).
    public static func isTerminating(_ stmt: StatementNode) -> Bool {
        if stmt is ReturnStatementNode { return true }
        if stmt is BreakStatementNode { return true }
        if stmt is ContinueStatementNode { return true }
        if stmt is ThrowStatementNode { return true }

        // A block is terminating if its last statement is terminating
        if let block = stmt as? BlockNode {
            if let last = block.statements.last {
                return isTerminating(last)
            }
        }

        // An if-else is terminating if both branches terminate
        if let ifStmt = stmt as? IfStatementNode {
            let thenTerminates = isTerminating(ifStmt.thenBlock)
            if let elseBlock = ifStmt.elseBlock {
                let elseTerminates = isTerminating(elseBlock)
                return thenTerminates && elseTerminates
            }
            return false
        }

        // guard always terminates via its else block
        if let guardStmt = stmt as? GuardStatementNode {
            return isTerminating(guardStmt.elseBlock)
        }

        return false
    }

    /// Returns true if all paths through the given block eventually return.
    public static func allPathsReturn(_ block: BlockNode) -> Bool {
        for stmt in block.statements {
            if isTerminating(stmt) {
                return true
            }
        }
        return false
    }

    /// Returns true if the given block contains a break statement.
    public static func containsBreak(_ block: BlockNode) -> Bool {
        for stmt in block.statements {
            if stmt is BreakStatementNode { return true }
            if let inner = stmt as? BlockNode, containsBreak(inner) { return true }
            if let ifStmt = stmt as? IfStatementNode {
                if containsBreak(ifStmt.thenBlock) { return true }
                if let elseBlock = ifStmt.elseBlock as? BlockNode, containsBreak(elseBlock) { return true }
            }
        }
        return false
    }

    /// Returns true if the given block contains a continue statement.
    public static func containsContinue(_ block: BlockNode) -> Bool {
        for stmt in block.statements {
            if stmt is ContinueStatementNode { return true }
            if let inner = stmt as? BlockNode, containsContinue(inner) { return true }
            if let ifStmt = stmt as? IfStatementNode {
                if containsContinue(ifStmt.thenBlock) { return true }
                if let elseBlock = ifStmt.elseBlock as? BlockNode, containsContinue(elseBlock) { return true }
            }
        }
        return false
    }
}
