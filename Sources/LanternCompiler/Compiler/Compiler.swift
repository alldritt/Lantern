import LanternVM

/// Compiles Lantern AST to bytecode for the LanternVM.
public final class BytecodeCompiler: @unchecked Sendable {
    var chunk = Chunk()
    var sourceMap = SourceMap()
    let scopeTracker = ScopeTracker()
    let symbolTable = SymbolTable()
    let diagnosticEngine = DiagnosticEngine()

    var variableRecords: [VariableRecord] = []
    var functionDebugInfo: [FunctionDebugInfo] = []
    var typeDebugInfo: [TypeDebugInfo] = []

    var breakTargets: [Int] = []
    var continueTargets: [Int] = []
    var loopDepth = 0
    var compilingMethodOfType: String? = nil
    /// All known property and method names for the type currently being compiled.
    /// Used to validate implicit self references at compile time.
    var currentTypePropertyNames: Set<String> = []
    var currentTypeMethodNames: Set<String> = []
    /// Set of @State property names for the current View type being compiled
    var statePropertyNames: Set<String> = []
    /// Set of @Binding property names for the current View type
    var bindingPropertyNames: Set<String> = []
    /// Set of @ObservedObject property names for the current View type
    var observedObjectPropertyNames: Set<String> = []
    /// Set of @Environment property names for the current View type
    var environmentPropertyNames: Set<String> = []
    /// Set of @AppStorage property names for the current View type (key → UserDefaults key)
    var appStorageProperties: [String: String] = [:]
    /// Accumulated @AppStorage mappings per type: [typeName: [propName: udKey]]
    public var allAppStorageMappings: [String: [String: String]] = [:]
    /// Set of @Published property names for the current class being compiled
    var publishedPropertyNames: Set<String> = []
    /// Whether the current type conforms to View (enables @State opcode emission)
    var isCompilingViewType: Bool = false
    /// When true, suppress the pop after expression statements (for implicit closure returns)
    var suppressExpressionPop: Bool = false
    /// Outer scope locals available for capture (set during closure compilation)
    var outerLocals: [ScopeTracker.Local] = []
    /// Captured variable names in order (built during closure body compilation)
    var capturedNames: [String] = []

    /// Tracks user-defined mutating methods: [typeName: Set<methodName>]
    var userMutatingMethods: [String: Set<String>] = [:]

    var currentFileName: String = "<input>"
    var sourceText: String = ""

    /// Names registered externally (e.g. bridge types) that should be treated as globals,
    /// not as implicit self.property inside type method bodies.
    public var externalGlobals: Set<String> = []

    /// Qualified names of static members (e.g. "Font.title") for implicit member resolution.
    public var externalStaticMembers: Set<String> = []

    /// Saved state for nested type compilation.
    struct TypeCompilationState {
        let isCompilingViewType: Bool
        let statePropertyNames: Set<String>
        let bindingPropertyNames: Set<String>
        let observedObjectPropertyNames: Set<String>
        let environmentPropertyNames: Set<String>
        let appStorageProperties: [String: String]
        let publishedPropertyNames: Set<String>
        let currentTypePropertyNames: Set<String>
        let currentTypeMethodNames: Set<String>
    }

    func saveTypeState() -> TypeCompilationState {
        TypeCompilationState(
            isCompilingViewType: isCompilingViewType,
            statePropertyNames: statePropertyNames,
            bindingPropertyNames: bindingPropertyNames,
            observedObjectPropertyNames: observedObjectPropertyNames,
            environmentPropertyNames: environmentPropertyNames,
            appStorageProperties: appStorageProperties,
            publishedPropertyNames: publishedPropertyNames,
            currentTypePropertyNames: currentTypePropertyNames,
            currentTypeMethodNames: currentTypeMethodNames
        )
    }

    func restoreTypeState(_ state: TypeCompilationState) {
        isCompilingViewType = state.isCompilingViewType
        statePropertyNames = state.statePropertyNames
        bindingPropertyNames = state.bindingPropertyNames
        observedObjectPropertyNames = state.observedObjectPropertyNames
        environmentPropertyNames = state.environmentPropertyNames
        appStorageProperties = state.appStorageProperties
        publishedPropertyNames = state.publishedPropertyNames
        currentTypePropertyNames = state.currentTypePropertyNames
        currentTypeMethodNames = state.currentTypeMethodNames
    }

    /// Extra stack slots allocated beyond parameters for local variables.
    static let localBufferSize = 16

    public init() {}

    // MARK: - Public API

    /// Compile source text directly.
    public func compile(source: String, fileName: String = "<input>") -> Result<CompiledProgram, CompilerDiagnostics> {
        let parser = LanternParser()
        let result = parser.parse(source: source, fileName: fileName)

        if result.diagnostics.contains(where: { $0.severity == .error }) {
            return .failure(CompilerDiagnostics(diagnostics: result.diagnostics))
        }

        guard let ast = result.ast else {
            return .failure(CompilerDiagnostics(diagnostics: [
                CompilerDiagnostic(message: "Failed to produce AST", severity: .error)
            ]))
        }

        return compile(ast: ast, fileName: fileName, sourceText: source)
    }

    /// Compile a pre-parsed AST.
    public func compile(ast: SourceFileNode, fileName: String = "<input>", sourceText: String = "") -> Result<CompiledProgram, CompilerDiagnostics> {
        reset()
        self.currentFileName = fileName
        self.sourceText = sourceText
        diagnosticEngine.setSource(sourceText, fileName: fileName)

        let fileIndex = sourceMap.addFile(fileName)
        _ = fileIndex

        // First pass: register top-level declarations
        registerTopLevelSymbols(ast)

        // Second pass: compile declarations first (hoisting)
        for statement in ast.statements {
            if statement is FunctionDeclarationNode || statement is StructDeclarationNode ||
               statement is ClassDeclarationNode || statement is EnumDeclarationNode ||
               statement is ExtensionNode {
                compileStatement(statement)
            }
        }

        // Third pass: compile remaining statements.
        // For the last expression statement, suppress the pop so the result
        // stays on the stack as the program's return value (displayed in preview).
        let topLevelStatements = ast.statements.filter {
            !($0 is FunctionDeclarationNode || $0 is StructDeclarationNode ||
              $0 is ClassDeclarationNode || $0 is EnumDeclarationNode ||
              $0 is ExtensionNode)
        }
        for (i, statement) in topLevelStatements.enumerated() {
            let isLast = (i == topLevelStatements.count - 1)
            if isLast, statement is ExpressionStatementNode {
                // Last top-level expression: keep result on stack
                compileExpression((statement as! ExpressionStatementNode).expression)
            } else {
                compileStatement(statement)
            }
        }

        // Emit halt
        emitLocation(.unknown)
        chunk.write(.halt)

        if diagnosticEngine.hasErrors {
            return .failure(diagnosticEngine.toDiagnostics())
        }

        let program = CompiledProgram(
            bytecode: chunk.bytecode,
            constantPool: chunk.constantPool,
            sourceMap: sourceMap,
            variableTable: variableRecords,
            functionTable: functionDebugInfo,
            typeTable: typeDebugInfo,
            sourceText: sourceText,
            fileName: fileName
        )
        return .success(program)
    }

    // MARK: - Reset

    private func reset() {
        chunk = Chunk()
        sourceMap = SourceMap()
        scopeTracker.reset()
        symbolTable.reset()
        diagnosticEngine.reset()
        variableRecords.removeAll()
        functionDebugInfo.removeAll()
        typeDebugInfo.removeAll()
        breakTargets.removeAll()
        continueTargets.removeAll()
        loopDepth = 0
    }

    // MARK: - Top-Level Registration

    private func registerTopLevelSymbols(_ ast: SourceFileNode) {
        for stmt in ast.statements {
            if let funcDecl = stmt as? FunctionDeclarationNode {
                symbolTable.register(funcDecl.name, kind: .function(
                    paramCount: funcDecl.parameters.count,
                    isAsync: funcDecl.isAsync,
                    isThrowing: funcDecl.isThrowing
                ), location: funcDecl.location)
            } else if let structDecl = stmt as? StructDeclarationNode {
                symbolTable.register(structDecl.name, kind: .type(.struct), location: structDecl.location)
            } else if let classDecl = stmt as? ClassDeclarationNode {
                symbolTable.register(classDecl.name, kind: .type(.class), location: classDecl.location)
            } else if let enumDecl = stmt as? EnumDeclarationNode {
                symbolTable.register(enumDecl.name, kind: .type(.enum), location: enumDecl.location)
                for enumCase in enumDecl.cases {
                    symbolTable.register(enumCase.name, kind: .enumCase(typeName: enumDecl.name), location: enumDecl.location)
                }
            } else if let varDecl = stmt as? VariableDeclarationNode {
                let hasInit = varDecl.initializer != nil
                symbolTable.register(varDecl.name, kind: .global(isMutable: varDecl.isMutable, isInitialized: hasInit), location: varDecl.location)
            }
        }
        // Register built-in enum cases for Result type
        let builtinLoc = SourceLocation(fileIndex: 0, line: 0, column: 0)
        symbolTable.register("success", kind: .enumCase(typeName: "Result"), location: builtinLoc)
        symbolTable.register("failure", kind: .enumCase(typeName: "Result"), location: builtinLoc)

        // Register core types so Type.member syntax compiles as qualified global lookup
        for typeName in ["Int", "Double", "Float", "Bool", "String", "Array", "Dictionary", "Result"] {
            symbolTable.register(typeName, kind: .type(.struct), location: builtinLoc)
        }
    }

    // MARK: - Source Location Helper

    func emitLocation(_ location: SourceLocation) {
        sourceMap.add(bytecodeOffset: chunk.count, location: location)
    }
}
