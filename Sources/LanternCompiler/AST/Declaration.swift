import LanternVM

// MARK: - Base Declaration

/// Base class for all declaration nodes.
public class DeclarationNode: StatementNode {
    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitDeclaration(self)
    }
}

// MARK: - Function Declaration

public final class FunctionDeclarationNode: DeclarationNode {
    public let name: String
    public let parameters: [Parameter]
    public let returnType: String?
    public let body: BlockNode
    public let isStatic: Bool
    public let isMutating: Bool
    public let isAsync: Bool
    public let isThrowing: Bool

    public struct Parameter {
        public let externalName: String?
        public let internalName: String
        public let typeAnnotation: String?
        public let defaultValue: ExpressionNode?

        public init(externalName: String? = nil, internalName: String, typeAnnotation: String? = nil, defaultValue: ExpressionNode? = nil) {
            self.externalName = externalName
            self.internalName = internalName
            self.typeAnnotation = typeAnnotation
            self.defaultValue = defaultValue
        }
    }

    public init(
        name: String,
        parameters: [Parameter],
        returnType: String? = nil,
        body: BlockNode,
        isStatic: Bool = false,
        isMutating: Bool = false,
        isAsync: Bool = false,
        isThrowing: Bool = false,
        location: SourceLocation
    ) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.body = body
        self.isStatic = isStatic
        self.isMutating = isMutating
        self.isAsync = isAsync
        self.isThrowing = isThrowing
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitFunctionDeclaration(self)
    }
}

// MARK: - Type Declarations

public final class StructDeclarationNode: DeclarationNode {
    public let name: String
    public let conformances: [String]
    public var members: [StatementNode]

    public init(name: String, conformances: [String] = [], members: [StatementNode], location: SourceLocation) {
        self.name = name
        self.conformances = conformances
        self.members = members
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitStructDeclaration(self)
    }
}

public final class ClassDeclarationNode: DeclarationNode {
    public let name: String
    public let superclass: String?
    public let conformances: [String]
    public var members: [StatementNode]

    public init(name: String, superclass: String? = nil, conformances: [String] = [], members: [StatementNode], location: SourceLocation) {
        self.name = name
        self.superclass = superclass
        self.conformances = conformances
        self.members = members
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitClassDeclaration(self)
    }
}

public final class EnumDeclarationNode: DeclarationNode {
    public let name: String
    public let conformances: [String]
    public var cases: [EnumCaseNode]
    public var members: [StatementNode]

    public init(name: String, conformances: [String] = [], cases: [EnumCaseNode], members: [StatementNode] = [], location: SourceLocation) {
        self.name = name
        self.conformances = conformances
        self.cases = cases
        self.members = members
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitEnumDeclaration(self)
    }
}

public final class EnumCaseNode: DeclarationNode {
    public let name: String
    public let associatedValues: [String]?
    public let rawValue: ExpressionNode?

    public init(name: String, associatedValues: [String]? = nil, rawValue: ExpressionNode? = nil, location: SourceLocation) {
        self.name = name
        self.associatedValues = associatedValues
        self.rawValue = rawValue
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitEnumCase(self)
    }
}

public final class ProtocolDeclarationNode: DeclarationNode {
    public let name: String
    public let inherits: [String]
    public var requirements: [StatementNode]

    public init(name: String, inherits: [String] = [], requirements: [StatementNode], location: SourceLocation) {
        self.name = name
        self.inherits = inherits
        self.requirements = requirements
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitProtocolDeclaration(self)
    }
}

public final class PropertyRequirementNode: DeclarationNode {
    public let name: String
    public let typeAnnotation: String?
    public let isSettable: Bool

    public init(name: String, typeAnnotation: String? = nil, isSettable: Bool = false, location: SourceLocation) {
        self.name = name
        self.typeAnnotation = typeAnnotation
        self.isSettable = isSettable
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitPropertyRequirement(self)
    }
}

public final class ExtensionNode: DeclarationNode {
    public let typeName: String
    public let conformances: [String]
    public var members: [StatementNode]

    public init(typeName: String, conformances: [String] = [], members: [StatementNode], location: SourceLocation) {
        self.typeName = typeName
        self.conformances = conformances
        self.members = members
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitExtension(self)
    }
}

// MARK: - Properties

public final class PropertyNode: DeclarationNode {
    public let name: String
    public let isMutable: Bool
    public let isStatic: Bool
    public let typeAnnotation: String?
    public var initializer: ExpressionNode?

    public init(name: String, isMutable: Bool, isStatic: Bool = false, typeAnnotation: String? = nil, initializer: ExpressionNode? = nil, location: SourceLocation) {
        self.name = name
        self.isMutable = isMutable
        self.isStatic = isStatic
        self.typeAnnotation = typeAnnotation
        self.initializer = initializer
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitProperty(self)
    }
}

public final class ComputedPropertyNode: DeclarationNode {
    public let name: String
    public let typeAnnotation: String?
    public let isStatic: Bool
    public let getter: BlockNode
    public let setter: BlockNode?

    public init(name: String, typeAnnotation: String? = nil, isStatic: Bool = false, getter: BlockNode, setter: BlockNode? = nil, location: SourceLocation) {
        self.name = name
        self.typeAnnotation = typeAnnotation
        self.isStatic = isStatic
        self.getter = getter
        self.setter = setter
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitComputedProperty(self)
    }
}

// MARK: - Initializer

public final class InitializerNode: DeclarationNode {
    public let parameters: [FunctionDeclarationNode.Parameter]
    public let isFailable: Bool
    public let body: BlockNode

    public init(parameters: [FunctionDeclarationNode.Parameter], isFailable: Bool = false, body: BlockNode, location: SourceLocation) {
        self.parameters = parameters
        self.isFailable = isFailable
        self.body = body
        super.init(location: location)
    }

    override public func accept<V: ASTVisitor>(_ visitor: V) throws -> V.Result {
        try visitor.visitInitializer(self)
    }
}
