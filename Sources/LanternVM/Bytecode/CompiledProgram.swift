/// The complete compiled output of the Lantern compiler.
public struct CompiledProgram: Sendable {
    public let bytecode: [UInt8]
    public let constantPool: ConstantPool
    public let sourceMap: SourceMap
    public let variableTable: [VariableRecord]
    public let functionTable: [FunctionDebugInfo]
    public let typeTable: [TypeDebugInfo]
    public let sourceText: String
    public let fileName: String

    public init(
        bytecode: [UInt8] = [],
        constantPool: ConstantPool = ConstantPool(),
        sourceMap: SourceMap = SourceMap(),
        variableTable: [VariableRecord] = [],
        functionTable: [FunctionDebugInfo] = [],
        typeTable: [TypeDebugInfo] = [],
        sourceText: String = "",
        fileName: String = "<input>"
    ) {
        self.bytecode = bytecode
        self.constantPool = constantPool
        self.sourceMap = sourceMap
        self.variableTable = variableTable
        self.functionTable = functionTable
        self.typeTable = typeTable
        self.sourceText = sourceText
        self.fileName = fileName
    }
}

// MARK: - Debug Metadata

public struct VariableRecord: Sendable {
    public let name: String
    public let slotIndex: UInt16
    public let scopeStart: Int
    public let scopeEnd: Int
    public let isMutable: Bool
    public let typeAnnotation: String?

    public init(name: String, slotIndex: UInt16, scopeStart: Int, scopeEnd: Int, isMutable: Bool, typeAnnotation: String? = nil) {
        self.name = name; self.slotIndex = slotIndex; self.scopeStart = scopeStart
        self.scopeEnd = scopeEnd; self.isMutable = isMutable; self.typeAnnotation = typeAnnotation
    }

    public func isInScope(at offset: Int) -> Bool { offset >= scopeStart && offset < scopeEnd }
}

public struct FunctionDebugInfo: Sendable {
    public let name: String
    public let parameterNames: [String]
    public let sourceRange: (start: SourceLocation, end: SourceLocation)
    public let bytecodeRange: (start: Int, end: Int)

    public init(name: String, parameterNames: [String], sourceRange: (start: SourceLocation, end: SourceLocation), bytecodeRange: (start: Int, end: Int)) {
        self.name = name; self.parameterNames = parameterNames
        self.sourceRange = sourceRange; self.bytecodeRange = bytecodeRange
    }
}

public struct TypeDebugInfo: Sendable {
    public let name: String
    public let kind: TypeKind
    public let properties: [PropertyInfo]
    public let methods: [String]
    public let conformances: [String]
    public let sourceRange: (start: SourceLocation, end: SourceLocation)

    public init(name: String, kind: TypeKind, properties: [PropertyInfo] = [], methods: [String] = [], conformances: [String] = [], sourceRange: (start: SourceLocation, end: SourceLocation)) {
        self.name = name; self.kind = kind; self.properties = properties
        self.methods = methods; self.conformances = conformances; self.sourceRange = sourceRange
    }
}

public struct PropertyInfo: Sendable {
    public let name: String
    public let typeAnnotation: String?
    public let isMutable: Bool
    public let isComputed: Bool
    public let isStatic: Bool

    public init(name: String, typeAnnotation: String? = nil, isMutable: Bool = true, isComputed: Bool = false, isStatic: Bool = false) {
        self.name = name; self.typeAnnotation = typeAnnotation; self.isMutable = isMutable
        self.isComputed = isComputed; self.isStatic = isStatic
    }
}
