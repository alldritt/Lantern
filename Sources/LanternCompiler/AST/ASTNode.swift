import LanternVM

/// Protocol all AST nodes conform to.
public protocol ASTNode: AnyObject {
    var location: SourceLocation { get }
    func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result
}

/// The root node representing a complete source file.
public final class SourceFileNode: ASTNode {
    public let location: SourceLocation
    public let fileName: String
    public var statements: [StatementNode]

    public init(fileName: String, statements: [StatementNode], location: SourceLocation = .unknown) {
        self.fileName = fileName
        self.statements = statements
        self.location = location
    }

    public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitSourceFile(self)
    }
}
