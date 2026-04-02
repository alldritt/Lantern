import LanternVM

/// Compiles Lantern AST to bytecode for the LanternVM.
public final class BytecodeCompiler: @unchecked Sendable {
    private var chunk = Chunk()
    private var sourceMap = SourceMap()
    private let scopeTracker = ScopeTracker()
    private let symbolTable = SymbolTable()
    private let diagnosticEngine = DiagnosticEngine()

    private var variableRecords: [VariableRecord] = []
    private var functionDebugInfo: [FunctionDebugInfo] = []
    private var typeDebugInfo: [TypeDebugInfo] = []

    private var breakTargets: [Int] = []
    private var continueTargets: [Int] = []
    private var loopDepth = 0

    private var currentFileName: String = "<input>"
    private var sourceText: String = ""

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
        _ = fileIndex // Used implicitly via location tracking

        // First pass: register top-level declarations
        registerTopLevelSymbols(ast)

        // Second pass: compile statements
        for statement in ast.statements {
            compileStatement(statement)
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
            } else if let varDecl = stmt as? VariableDeclarationNode {
                symbolTable.register(varDecl.name, kind: .global(isMutable: varDecl.isMutable), location: varDecl.location)
            }
        }
    }

    // MARK: - Statement Compilation

    private func compileStatement(_ stmt: StatementNode) {
        if let varDecl = stmt as? VariableDeclarationNode {
            compileVariableDeclaration(varDecl)
        } else if let exprStmt = stmt as? ExpressionStatementNode {
            compileExpression(exprStmt.expression)
            chunk.write(.pop)
        } else if let ifStmt = stmt as? IfStatementNode {
            compileIfStatement(ifStmt)
        } else if let guardStmt = stmt as? GuardStatementNode {
            compileGuardStatement(guardStmt)
        } else if let whileStmt = stmt as? WhileStatementNode {
            compileWhileStatement(whileStmt)
        } else if let forStmt = stmt as? ForInStatementNode {
            compileForInStatement(forStmt)
        } else if let returnStmt = stmt as? ReturnStatementNode {
            compileReturnStatement(returnStmt)
        } else if let breakStmt = stmt as? BreakStatementNode {
            compileBreakStatement(breakStmt)
        } else if let continueStmt = stmt as? ContinueStatementNode {
            compileContinueStatement(continueStmt)
        } else if let throwStmt = stmt as? ThrowStatementNode {
            compileThrowStatement(throwStmt)
        } else if let doStmt = stmt as? DoCatchStatementNode {
            compileDoCatchStatement(doStmt)
        } else if let deferStmt = stmt as? DeferStatementNode {
            compileDeferStatement(deferStmt)
        } else if let switchStmt = stmt as? SwitchStatementNode {
            compileSwitchStatement(switchStmt)
        } else if let block = stmt as? BlockNode {
            compileBlock(block)
        } else if let funcDecl = stmt as? FunctionDeclarationNode {
            compileFunctionDeclaration(funcDecl)
        } else if let structDecl = stmt as? StructDeclarationNode {
            compileStructDeclaration(structDecl)
        } else if let classDecl = stmt as? ClassDeclarationNode {
            compileClassDeclaration(classDecl)
        } else if let enumDecl = stmt as? EnumDeclarationNode {
            compileEnumDeclaration(enumDecl)
        } else if let protocolDecl = stmt as? ProtocolDeclarationNode {
            // Protocols are type-checked but not compiled to bytecode
            _ = protocolDecl
        } else if let extensionDecl = stmt as? ExtensionNode {
            compileExtension(extensionDecl)
        } else {
            diagnosticEngine.error("Unsupported statement type: \(type(of: stmt))", at: stmt.location)
        }
    }

    private func compileBlock(_ block: BlockNode) {
        scopeTracker.pushScope()
        let scopeStart = chunk.count
        for stmt in block.statements {
            compileStatement(stmt)
        }
        let removed = scopeTracker.popScope()
        let scopeEnd = chunk.count
        for local in removed {
            variableRecords.append(VariableRecord(
                name: local.name,
                slotIndex: local.slot,
                scopeStart: scopeStart,
                scopeEnd: scopeEnd,
                isMutable: local.isMutable,
                typeAnnotation: local.typeAnnotation
            ))
            chunk.write(.pop)
        }
    }

    private func compileVariableDeclaration(_ decl: VariableDeclarationNode) {
        emitLocation(decl.location)

        if let initializer = decl.initializer {
            compileExpression(initializer)
        } else {
            chunk.write(.constNil)
        }

        if scopeTracker.currentDepth == 0 {
            // Global variable — store in environment, don't allocate a stack slot
            symbolTable.register(decl.name, kind: .global(isMutable: decl.isMutable), location: decl.location)
            let nameIndex = chunk.constantPool.addString(decl.name)
            Instruction.storeGlobal(nameIndex, into: &chunk)
        } else {
            // Local variable — allocate a stack slot
            let slot = scopeTracker.declare(name: decl.name, isMutable: decl.isMutable, typeAnnotation: decl.typeAnnotation)
            Instruction.storeLocal(slot, into: &chunk)
        }
    }

    private func compileIfStatement(_ stmt: IfStatementNode) {
        emitLocation(stmt.location)

        if let binding = stmt.optionalBinding {
            // if let x = expr { ... }
            compileExpression(binding.value)
            chunk.write(.dup)
            let jumpElse = Instruction.jumpIfFalse(into: &chunk)

            // Unwrap and bind
            chunk.write(.unwrapOptional)
            scopeTracker.pushScope()
            let slot = scopeTracker.declare(name: binding.name, isMutable: binding.isMutable)
            Instruction.storeLocal(slot, into: &chunk)

            for s in stmt.thenBlock.statements {
                compileStatement(s)
            }
            let removed = scopeTracker.popScope()
            for _ in removed { chunk.write(.pop) }

            let jumpEnd = Instruction.jump(into: &chunk)
            Instruction.patchJump(at: jumpElse, in: &chunk)
            chunk.write(.pop) // Pop the nil

            if let elseBlock = stmt.elseBlock {
                compileStatement(elseBlock)
            }
            Instruction.patchJump(at: jumpEnd, in: &chunk)
        } else if let condition = stmt.condition {
            compileExpression(condition)
            let jumpElse = Instruction.jumpIfFalse(into: &chunk)

            compileBlock(stmt.thenBlock)

            let jumpEnd = Instruction.jump(into: &chunk)
            Instruction.patchJump(at: jumpElse, in: &chunk)

            if let elseBlock = stmt.elseBlock {
                compileStatement(elseBlock)
            }
            Instruction.patchJump(at: jumpEnd, in: &chunk)
        }
    }

    private func compileGuardStatement(_ stmt: GuardStatementNode) {
        emitLocation(stmt.location)

        if let binding = stmt.optionalBinding {
            compileExpression(binding.value)
            chunk.write(.dup)
            let jumpElse = Instruction.jumpIfFalse(into: &chunk)

            // Bind the unwrapped value
            chunk.write(.unwrapOptional)
            let slot = scopeTracker.declare(name: binding.name, isMutable: binding.isMutable)
            Instruction.storeLocal(slot, into: &chunk)

            let jumpEnd = Instruction.jump(into: &chunk)
            Instruction.patchJump(at: jumpElse, in: &chunk)
            chunk.write(.pop)

            compileBlock(stmt.elseBlock)
            Instruction.patchJump(at: jumpEnd, in: &chunk)
        } else if let condition = stmt.condition {
            compileExpression(condition)
            let jumpPastElse = Instruction.jumpIfTrue(into: &chunk)
            compileBlock(stmt.elseBlock)
            Instruction.patchJump(at: jumpPastElse, in: &chunk)
        }
    }

    private func compileWhileStatement(_ stmt: WhileStatementNode) {
        emitLocation(stmt.location)
        let loopStart = chunk.count

        compileExpression(stmt.condition)
        let exitJump = Instruction.jumpIfFalse(into: &chunk)

        loopDepth += 1
        let oldBreakTargets = breakTargets
        let oldContinueTargets = continueTargets
        breakTargets = []
        continueTargets = []

        compileBlock(stmt.body)

        // Loop back to condition check
        chunk.write(.loop)
        let offset = loopStart - (chunk.count + 2) // negative: jump backward
        chunk.writeI16(Int16(offset))

        Instruction.patchJump(at: exitJump, in: &chunk)

        // Patch break/continue targets
        for bp in breakTargets {
            Instruction.patchJump(at: bp, in: &chunk)
        }
        for cp in continueTargets {
            chunk.patchI16(at: cp, value: Int16(loopStart - (cp + 2)))
        }

        breakTargets = oldBreakTargets
        continueTargets = oldContinueTargets
        loopDepth -= 1
    }

    private func compileForInStatement(_ stmt: ForInStatementNode) {
        emitLocation(stmt.location)

        // Check if iterable is a range expression (0..<n or 0...n)
        if let rangeExpr = stmt.iterable as? BinaryExpressionNode,
           (rangeExpr.op == .halfOpenRange || rangeExpr.op == .closedRange) {
            compileForInRange(stmt, rangeExpr: rangeExpr)
            return
        }

        // Array iteration: evaluate iterable, iterate with index
        compileForInArray(stmt)
    }

    private func compileForInRange(_ stmt: ForInStatementNode, rangeExpr: BinaryExpressionNode) {
        let isInclusive = rangeExpr.op == .closedRange

        scopeTracker.pushScope()

        // Compile and store end value
        compileExpression(rangeExpr.right)
        let endSlot = scopeTracker.declare(name: "__end", isMutable: false)
        Instruction.storeLocal(endSlot, into: &chunk)

        // Compile and store start as loop variable
        compileExpression(rangeExpr.left)
        let varSlot = scopeTracker.declare(name: stmt.variableName, isMutable: true)
        Instruction.storeLocal(varSlot, into: &chunk)

        let loopStart = chunk.count

        // Check: variable < end (or <= for inclusive)
        Instruction.loadLocal(varSlot, into: &chunk)
        Instruction.loadLocal(endSlot, into: &chunk)
        chunk.write(isInclusive ? .lte : .lt)
        let exitJump = Instruction.jumpIfFalse(into: &chunk)

        loopDepth += 1
        let oldBreakTargets = breakTargets
        let oldContinueTargets = continueTargets
        breakTargets = []
        continueTargets = []

        // Compile body
        for s in stmt.body.statements {
            compileStatement(s)
        }

        // Increment loop variable
        Instruction.loadLocal(varSlot, into: &chunk)
        Instruction.constInt(1, into: &chunk)
        chunk.write(.add)
        Instruction.storeLocal(varSlot, into: &chunk)

        // Loop back
        chunk.write(.loop)
        chunk.writeI16(Int16(loopStart - (chunk.count + 2)))

        Instruction.patchJump(at: exitJump, in: &chunk)

        for bp in breakTargets { Instruction.patchJump(at: bp, in: &chunk) }
        for cp in continueTargets { chunk.patchI16(at: cp, value: Int16(loopStart - (cp + 2))) }

        let removed = scopeTracker.popScope()
        for _ in removed { chunk.write(.pop) }

        breakTargets = oldBreakTargets
        continueTargets = oldContinueTargets
        loopDepth -= 1
    }

    private func compileForInArray(_ stmt: ForInStatementNode) {
        compileExpression(stmt.iterable)

        scopeTracker.pushScope()

        // Store the array
        let arraySlot = scopeTracker.declare(name: "__array", isMutable: false)
        Instruction.storeLocal(arraySlot, into: &chunk)

        // Get count via property
        Instruction.loadLocal(arraySlot, into: &chunk)
        let countNameIdx = chunk.constantPool.addPropertyName("count")
        Instruction.getProperty(countNameIdx, into: &chunk)
        let countSlot = scopeTracker.declare(name: "__count", isMutable: false)
        Instruction.storeLocal(countSlot, into: &chunk)

        // Index = 0
        Instruction.constInt(0, into: &chunk)
        let indexSlot = scopeTracker.declare(name: "__index", isMutable: true)
        Instruction.storeLocal(indexSlot, into: &chunk)

        let loopStart = chunk.count

        // Check index < count
        Instruction.loadLocal(indexSlot, into: &chunk)
        Instruction.loadLocal(countSlot, into: &chunk)
        chunk.write(.lt)
        let exitJump = Instruction.jumpIfFalse(into: &chunk)

        // Get element: array[index]
        Instruction.loadLocal(arraySlot, into: &chunk)
        Instruction.loadLocal(indexSlot, into: &chunk)
        chunk.write(.getIndex)
        let varSlot = scopeTracker.declare(name: stmt.variableName, isMutable: false)
        Instruction.storeLocal(varSlot, into: &chunk)

        loopDepth += 1
        let oldBreakTargets = breakTargets
        let oldContinueTargets = continueTargets
        breakTargets = []
        continueTargets = []

        for s in stmt.body.statements { compileStatement(s) }

        // Increment index
        Instruction.loadLocal(indexSlot, into: &chunk)
        Instruction.constInt(1, into: &chunk)
        chunk.write(.add)
        Instruction.storeLocal(indexSlot, into: &chunk)

        // Loop back
        chunk.write(.loop)
        chunk.writeI16(Int16(loopStart - (chunk.count + 2)))

        Instruction.patchJump(at: exitJump, in: &chunk)

        for bp in breakTargets { Instruction.patchJump(at: bp, in: &chunk) }
        for cp in continueTargets { chunk.patchI16(at: cp, value: Int16(loopStart - (cp + 2))) }

        let removed = scopeTracker.popScope()
        for _ in removed { chunk.write(.pop) }

        breakTargets = oldBreakTargets
        continueTargets = oldContinueTargets
        loopDepth -= 1
    }

    private func compileReturnStatement(_ stmt: ReturnStatementNode) {
        emitLocation(stmt.location)
        if let value = stmt.value {
            compileExpression(value)
            chunk.write(.return_)
        } else {
            chunk.write(.returnVoid)
        }
    }

    private func compileBreakStatement(_ stmt: BreakStatementNode) {
        emitLocation(stmt.location)
        if loopDepth == 0 {
            diagnosticEngine.error("'break' outside of loop", at: stmt.location)
            return
        }
        let patchOffset = Instruction.jump(into: &chunk)
        breakTargets.append(patchOffset)
    }

    private func compileContinueStatement(_ stmt: ContinueStatementNode) {
        emitLocation(stmt.location)
        if loopDepth == 0 {
            diagnosticEngine.error("'continue' outside of loop", at: stmt.location)
            return
        }
        chunk.write(.loop)
        let patchOffset = chunk.count
        chunk.writeI16(0)
        continueTargets.append(patchOffset)
    }

    private func compileThrowStatement(_ stmt: ThrowStatementNode) {
        emitLocation(stmt.location)
        compileExpression(stmt.expression)
        chunk.write(.throw_)
    }

    private func compileDoCatchStatement(_ stmt: DoCatchStatementNode) {
        emitLocation(stmt.location)
        // Simplified: compile body, jump over catch if no error
        compileBlock(stmt.body)
        let jumpEnd = Instruction.jump(into: &chunk)

        for clause in stmt.catchClauses {
            if let pattern = clause.pattern {
                let slot = scopeTracker.declare(name: pattern, isMutable: false)
                Instruction.storeLocal(slot, into: &chunk)
            }
            compileBlock(clause.body)
        }

        Instruction.patchJump(at: jumpEnd, in: &chunk)
    }

    private func compileDeferStatement(_ stmt: DeferStatementNode) {
        emitLocation(stmt.location)
        // Compile the deferred block's offset
        let deferJump = Instruction.jump(into: &chunk)

        let deferStart = chunk.count
        compileBlock(stmt.body)
        chunk.write(.returnVoid)

        Instruction.patchJump(at: deferJump, in: &chunk)
        chunk.write(.deferPush)
        chunk.writeU16(UInt16(deferStart))
    }

    private func compileSwitchStatement(_ stmt: SwitchStatementNode) {
        emitLocation(stmt.location)
        compileExpression(stmt.subject)

        var endJumps: [Int] = []

        for switchCase in stmt.cases {
            if switchCase.isDefault {
                chunk.write(.pop) // Pop the subject
                compileBlock(switchCase.body)
                let jump = Instruction.jump(into: &chunk)
                endJumps.append(jump)
            } else {
                var caseJumps: [Int] = []
                for pattern in switchCase.patterns {
                    chunk.write(.dup)
                    switch pattern {
                    case .expression(let expr):
                        compileExpression(expr)
                    case .identifier(let name):
                        Instruction.constString(name, into: &chunk)
                    case .wildcard:
                        Instruction.constBool(true, into: &chunk)
                        let jump = Instruction.jumpIfTrue(into: &chunk)
                        caseJumps.append(jump)
                        continue
                    }
                    chunk.write(.eq)
                    let jump = Instruction.jumpIfTrue(into: &chunk)
                    caseJumps.append(jump)
                }

                let nextCase = Instruction.jump(into: &chunk)

                for cj in caseJumps {
                    Instruction.patchJump(at: cj, in: &chunk)
                }

                chunk.write(.pop) // Pop the subject
                compileBlock(switchCase.body)
                let endJump = Instruction.jump(into: &chunk)
                endJumps.append(endJump)

                Instruction.patchJump(at: nextCase, in: &chunk)
            }
        }

        chunk.write(.pop) // Pop subject if no case matched

        for ej in endJumps {
            Instruction.patchJump(at: ej, in: &chunk)
        }
    }

    // MARK: - Declaration Compilation

    private func compileFunctionDeclaration(_ decl: FunctionDeclarationNode) {
        emitLocation(decl.location)

        // Jump over the function body (it's inlined in the shared bytecode)
        let jumpOver = Instruction.jump(into: &chunk)
        let bodyStart = chunk.count

        // Compile function body inline — each function has its own slot space
        let savedSlots = scopeTracker.saveSlotState()
        scopeTracker.restoreSlotState(0)
        scopeTracker.pushScope()
        for param in decl.parameters {
            scopeTracker.declare(name: param.internalName, isMutable: false, typeAnnotation: param.typeAnnotation)
        }

        for stmt in decl.body.statements {
            compileStatement(stmt)
        }

        // Implicit return void if last instruction is not a return
        if chunk.bytecode.isEmpty || chunk.bytecode.last != Opcode.return_.rawValue {
            chunk.write(.returnVoid)
        }

        _ = scopeTracker.popScope()
        scopeTracker.restoreSlotState(savedSlots)

        let bodyEnd = chunk.count
        Instruction.patchJump(at: jumpOver, in: &chunk)

        let parameters = decl.parameters.map { param in
            ParameterInfo(
                label: param.externalName,
                name: param.internalName,
                typeAnnotation: param.typeAnnotation,
                hasDefault: param.defaultValue != nil
            )
        }

        let funcRef = FunctionRef(
            name: decl.name,
            parameters: parameters,
            localCount: UInt16(decl.parameters.count + 16), // room for locals
            isAsync: decl.isAsync,
            isThrowing: decl.isThrowing,
            bytecode: [] // body is inline in shared bytecode
        )

        let funcIndex = chunk.constantPool.addFunction(funcRef)

        // Record debug info with bytecode range
        functionDebugInfo.append(FunctionDebugInfo(
            name: decl.name,
            parameterNames: decl.parameters.map(\.internalName),
            sourceRange: (start: decl.location, end: decl.location),
            bytecodeRange: (start: bodyStart, end: bodyEnd)
        ))

        // Store function as global
        let nameIndex = chunk.constantPool.addString(decl.name)
        chunk.write(.closure)
        chunk.writeU16(funcIndex)
        chunk.write(0) // No captures for top-level functions
        Instruction.storeGlobal(nameIndex, into: &chunk)
    }

    private func compileStructDeclaration(_ decl: StructDeclarationNode) {
        emitLocation(decl.location)
        let typeIndex = chunk.constantPool.addTypeName(decl.name)

        var properties: [PropertyInfo] = []
        for member in decl.members {
            if let prop = member as? VariableDeclarationNode {
                properties.append(PropertyInfo(
                    name: prop.name,
                    typeAnnotation: prop.typeAnnotation,
                    isMutable: prop.isMutable
                ))
            } else if let prop = member as? PropertyNode {
                properties.append(PropertyInfo(
                    name: prop.name,
                    typeAnnotation: prop.typeAnnotation,
                    isMutable: prop.isMutable,
                    isStatic: prop.isStatic
                ))
            } else if let funcDecl = member as? FunctionDeclarationNode {
                compileFunctionDeclaration(funcDecl)
            }
        }

        typeDebugInfo.append(TypeDebugInfo(
            name: decl.name,
            kind: .struct,
            properties: properties,
            methods: decl.members.compactMap { ($0 as? FunctionDeclarationNode)?.name },
            conformances: decl.conformances,
            sourceRange: (start: decl.location, end: decl.location)
        ))

        // Generate memberwise initializer as a native function
        // The VM will register this when executing
        let propNames = properties.map(\.name)
        let structName = decl.name

        // Emit CONSTRUCT opcode approach: store a native init in the global
        // We emit a closure that creates an InstanceRef
        let jumpOver = Instruction.jump(into: &chunk)
        let bodyStart = chunk.count

        // The init body: create instance from args on stack
        // Args are at local slots 0, 1, ...
        let savedSlots = scopeTracker.saveSlotState()
        scopeTracker.restoreSlotState(0)
        scopeTracker.pushScope()
        for prop in propNames {
            scopeTracker.declare(name: prop, isMutable: false)
        }

        // Build instance: push all property values, then construct
        for (i, _) in propNames.enumerated() {
            Instruction.loadLocal(UInt16(i), into: &chunk)
        }
        Instruction.construct(typeIndex, argCount: UInt8(propNames.count), into: &chunk)
        chunk.write(.return_)

        _ = scopeTracker.popScope()
        scopeTracker.restoreSlotState(savedSlots)

        let bodyEnd = chunk.count
        Instruction.patchJump(at: jumpOver, in: &chunk)

        let initParams = propNames.map { ParameterInfo(label: $0, name: $0) }
        let initRef = FunctionRef(
            name: structName,
            parameters: initParams,
            localCount: UInt16(propNames.count + 4),
            bytecode: []
        )
        let funcIndex = chunk.constantPool.addFunction(initRef)

        functionDebugInfo.append(FunctionDebugInfo(
            name: structName,
            parameterNames: propNames,
            sourceRange: (start: decl.location, end: decl.location),
            bytecodeRange: (start: bodyStart, end: bodyEnd)
        ))

        // Store as global
        let nameIndex = chunk.constantPool.addString(structName)
        chunk.write(.closure)
        chunk.writeU16(funcIndex)
        chunk.write(0)
        Instruction.storeGlobal(nameIndex, into: &chunk)
    }

    private func compileClassDeclaration(_ decl: ClassDeclarationNode) {
        emitLocation(decl.location)
        let typeIndex = chunk.constantPool.addTypeName(decl.name)

        var properties: [PropertyInfo] = []
        for member in decl.members {
            if let prop = member as? VariableDeclarationNode {
                properties.append(PropertyInfo(
                    name: prop.name,
                    typeAnnotation: prop.typeAnnotation,
                    isMutable: prop.isMutable
                ))
            } else if let funcDecl = member as? FunctionDeclarationNode {
                compileFunctionDeclaration(funcDecl)
            }
        }

        typeDebugInfo.append(TypeDebugInfo(
            name: decl.name,
            kind: .class,
            properties: properties,
            methods: decl.members.compactMap { ($0 as? FunctionDeclarationNode)?.name },
            conformances: decl.conformances,
            sourceRange: (start: decl.location, end: decl.location)
        ))
        _ = typeIndex
    }

    private func compileEnumDeclaration(_ decl: EnumDeclarationNode) {
        emitLocation(decl.location)
        let typeIndex = chunk.constantPool.addTypeName(decl.name)

        for member in decl.members {
            if let funcDecl = member as? FunctionDeclarationNode {
                compileFunctionDeclaration(funcDecl)
            }
        }

        typeDebugInfo.append(TypeDebugInfo(
            name: decl.name,
            kind: .enum,
            methods: decl.members.compactMap { ($0 as? FunctionDeclarationNode)?.name },
            conformances: decl.conformances,
            sourceRange: (start: decl.location, end: decl.location)
        ))
        _ = typeIndex
    }

    private func compileExtension(_ ext: ExtensionNode) {
        for member in ext.members {
            compileStatement(member)
        }
    }

    // MARK: - Expression Compilation

    private func compileExpression(_ expr: ExpressionNode) {
        emitLocation(expr.location)

        if let intLit = expr as? IntLiteralNode {
            Instruction.constInt(intLit.value, into: &chunk)
        } else if let doubleLit = expr as? DoubleLiteralNode {
            Instruction.constDouble(doubleLit.value, into: &chunk)
        } else if let boolLit = expr as? BoolLiteralNode {
            Instruction.constBool(boolLit.value, into: &chunk)
        } else if let stringLit = expr as? StringLiteralNode {
            Instruction.constString(stringLit.value, into: &chunk)
        } else if expr is NilLiteralNode {
            chunk.write(.constNil)
        } else if let interpolation = expr as? StringInterpolationNode {
            for segment in interpolation.segments {
                compileExpression(segment)
            }
            chunk.write(.interpolate)
            chunk.write(UInt8(interpolation.segments.count))
        } else if let ident = expr as? IdentifierNode {
            compileIdentifier(ident)
        } else if let member = expr as? MemberAccessNode {
            compileExpression(member.object)
            let nameIndex = chunk.constantPool.addPropertyName(member.member)
            Instruction.getProperty(nameIndex, into: &chunk)
        } else if expr is SelfNode {
            Instruction.loadLocal(0, into: &chunk) // self is always slot 0
        } else if let typeRef = expr as? TypeReferenceNode {
            let nameIndex = chunk.constantPool.addString(typeRef.typeName)
            Instruction.loadGlobal(nameIndex, into: &chunk)
        } else if let binary = expr as? BinaryExpressionNode {
            compileBinaryExpression(binary)
        } else if let unary = expr as? UnaryExpressionNode {
            compileExpression(unary.operand)
            switch unary.op {
            case .negate: chunk.write(.neg)
            case .not: chunk.write(.not)
            case .bitwiseNot:
                diagnosticEngine.warning("Bitwise NOT not yet implemented", at: unary.location)
                chunk.write(.not)
            }
        } else if let call = expr as? FunctionCallNode {
            compileFunctionCall(call)
        } else if let sub = expr as? SubscriptNode {
            compileExpression(sub.object)
            compileExpression(sub.index)
            chunk.write(.getIndex)
        } else if let array = expr as? ArrayLiteralNode {
            for element in array.elements {
                compileExpression(element)
            }
            chunk.write(.makeArray)
            chunk.writeU16(UInt16(array.elements.count))
        } else if let dict = expr as? DictionaryLiteralNode {
            for entry in dict.entries {
                compileExpression(entry.key)
                compileExpression(entry.value)
            }
            chunk.write(.makeDict)
            chunk.writeU16(UInt16(dict.entries.count))
        } else if let closure = expr as? ClosureExpressionNode {
            compileClosureExpression(closure)
        } else if let forceUnwrap = expr as? ForceUnwrapNode {
            compileExpression(forceUnwrap.expression)
            chunk.write(.unwrapOptional)
        } else if let optChain = expr as? OptionalChainingNode {
            compileExpression(optChain.expression)
            let jumpOffset = Instruction.jump(into: &chunk)
            chunk.write(.optionalChain)
            chunk.writeI16(0)
            Instruction.patchJump(at: jumpOffset, in: &chunk)
        } else if let tryExpr = expr as? TryExpressionNode {
            compileExpression(tryExpr.expression)
            if tryExpr.kind == .tryOptional {
                chunk.write(.wrapOptional)
            }
        } else if let awaitExpr = expr as? AwaitExpressionNode {
            compileExpression(awaitExpr.expression)
        } else if let assign = expr as? AssignmentNode {
            compileAssignment(assign)
        } else if let ternary = expr as? TernaryExpressionNode {
            compileExpression(ternary.condition)
            let jumpElse = Instruction.jumpIfFalse(into: &chunk)
            compileExpression(ternary.thenExpr)
            let jumpEnd = Instruction.jump(into: &chunk)
            Instruction.patchJump(at: jumpElse, in: &chunk)
            compileExpression(ternary.elseExpr)
            Instruction.patchJump(at: jumpEnd, in: &chunk)
        } else {
            diagnosticEngine.error("Unsupported expression type: \(type(of: expr))", at: expr.location)
            chunk.write(.constNil)
        }
    }

    private func compileIdentifier(_ ident: IdentifierNode) {
        // Check locals first (inner to outer scope)
        if let local = scopeTracker.resolve(ident.name) {
            Instruction.loadLocal(local.slot, into: &chunk)
        } else {
            // Global or unresolved — load from environment
            let nameIndex = chunk.constantPool.addString(ident.name)
            Instruction.loadGlobal(nameIndex, into: &chunk)
        }
    }

    private func compileBinaryExpression(_ binary: BinaryExpressionNode) {
        // Short-circuit for && and ||
        switch binary.op {
        case .and:
            compileExpression(binary.left)
            let jumpFalse = Instruction.jumpIfFalse(into: &chunk)
            compileExpression(binary.right)
            let jumpEnd = Instruction.jump(into: &chunk)
            Instruction.patchJump(at: jumpFalse, in: &chunk)
            Instruction.constBool(false, into: &chunk)
            Instruction.patchJump(at: jumpEnd, in: &chunk)
            return
        case .or:
            compileExpression(binary.left)
            let jumpTrue = Instruction.jumpIfTrue(into: &chunk)
            compileExpression(binary.right)
            let jumpEnd = Instruction.jump(into: &chunk)
            Instruction.patchJump(at: jumpTrue, in: &chunk)
            Instruction.constBool(true, into: &chunk)
            Instruction.patchJump(at: jumpEnd, in: &chunk)
            return
        case .nilCoalescing:
            compileExpression(binary.left)
            chunk.write(.dup)
            let jumpHasValue = Instruction.jumpIfTrue(into: &chunk)
            chunk.write(.pop)
            compileExpression(binary.right)
            Instruction.patchJump(at: jumpHasValue, in: &chunk)
            return
        case .closedRange:
            compileExpression(binary.left)
            compileExpression(binary.right)
            chunk.write(.makeRange)
            chunk.write(1) // inclusive
            return
        case .halfOpenRange:
            compileExpression(binary.left)
            compileExpression(binary.right)
            chunk.write(.makeRange)
            chunk.write(0) // exclusive
            return
        default:
            break
        }

        compileExpression(binary.left)
        compileExpression(binary.right)

        switch binary.op {
        case .add: chunk.write(.add)
        case .subtract: chunk.write(.sub)
        case .multiply: chunk.write(.mul)
        case .divide: chunk.write(.div)
        case .modulo: chunk.write(.mod)
        case .equal: chunk.write(.eq)
        case .notEqual: chunk.write(.neq)
        case .lessThan: chunk.write(.lt)
        case .greaterThan: chunk.write(.gt)
        case .lessThanOrEqual: chunk.write(.lte)
        case .greaterThanOrEqual: chunk.write(.gte)
        default:
            diagnosticEngine.warning("Operator \(binary.op.rawValue) not fully implemented", at: binary.location)
            chunk.write(.add)
        }
    }

    private func compileFunctionCall(_ call: FunctionCallNode) {
        // Check if it's a method call
        if let memberAccess = call.callee as? MemberAccessNode {
            compileExpression(memberAccess.object)
            for arg in call.arguments {
                compileExpression(arg.value)
            }
            let nameIndex = chunk.constantPool.addMethodName(memberAccess.member)
            Instruction.callMethod(nameIndex, argCount: UInt8(call.arguments.count), into: &chunk)
        } else {
            compileExpression(call.callee)
            for arg in call.arguments {
                compileExpression(arg.value)
            }
            Instruction.call(argCount: UInt8(call.arguments.count), into: &chunk)
        }
    }

    private func compileClosureExpression(_ closure: ClosureExpressionNode) {
        let closureName = "<closure_\(chunk.count)>"

        // Jump over the closure body
        let jumpOver = Instruction.jump(into: &chunk)
        let bodyStart = chunk.count

        let savedSlots = scopeTracker.saveSlotState()
        scopeTracker.restoreSlotState(0)
        scopeTracker.pushScope()
        for param in closure.parameters {
            scopeTracker.declare(name: param, isMutable: false)
        }

        for stmt in closure.body.statements {
            compileStatement(stmt)
        }

        // If last statement is an expression (implicit return), emit return
        if chunk.bytecode.last != Opcode.return_.rawValue && chunk.bytecode.last != Opcode.returnVoid.rawValue {
            // Check if last compiled statement was an expression (the value is on stack)
            // For single-expression closures like { n * n }, the expression result is on stack
            if closure.body.statements.count == 1 && closure.body.statements.first is ExpressionStatementNode {
                // Remove the trailing pop (expression statement adds pop) and add return
                if chunk.bytecode.last == Opcode.pop.rawValue {
                    chunk.bytecode.removeLast()
                }
                chunk.write(.return_)
            } else {
                chunk.write(.returnVoid)
            }
        }

        _ = scopeTracker.popScope()
        scopeTracker.restoreSlotState(savedSlots)
        let bodyEnd = chunk.count
        Instruction.patchJump(at: jumpOver, in: &chunk)

        let params = closure.parameters.map { ParameterInfo(name: $0) }

        let funcRef = FunctionRef(
            name: closureName,
            parameters: params,
            localCount: UInt16(closure.parameters.count + 16),
            bytecode: []
        )

        let funcIndex = chunk.constantPool.addFunction(funcRef)

        // Record in function table for VM dispatch
        functionDebugInfo.append(FunctionDebugInfo(
            name: closureName,
            parameterNames: closure.parameters,
            sourceRange: (start: closure.location, end: closure.location),
            bytecodeRange: (start: bodyStart, end: bodyEnd)
        ))

        chunk.write(.closure)
        chunk.writeU16(funcIndex)
        chunk.write(0) // captures count (simplified — capture support pending)
    }

    private func compileAssignment(_ assign: AssignmentNode) {
        compileExpression(assign.value)

        if let ident = assign.target as? IdentifierNode {
            if let local = scopeTracker.resolve(ident.name) {
                if !local.isMutable {
                    diagnosticEngine.error("Cannot assign to immutable variable '\(ident.name)'", at: assign.location)
                }
                chunk.write(.dup)
                Instruction.storeLocal(local.slot, into: &chunk)
            } else {
                // Global variable
                chunk.write(.dup)
                let nameIndex = chunk.constantPool.addString(ident.name)
                Instruction.storeGlobal(nameIndex, into: &chunk)
            }
        } else if let member = assign.target as? MemberAccessNode {
            compileExpression(member.object)
            chunk.write(.dup) // Keep the object and value around
            let nameIndex = chunk.constantPool.addPropertyName(member.member)
            Instruction.setProperty(nameIndex, into: &chunk)
        } else if let sub = assign.target as? SubscriptNode {
            compileExpression(sub.object)
            compileExpression(sub.index)
            chunk.write(.setIndex)
        } else {
            diagnosticEngine.error("Invalid assignment target", at: assign.location)
        }
    }

    // MARK: - Source Map

    private func emitLocation(_ location: SourceLocation) {
        sourceMap.add(bytecodeOffset: chunk.count, location: location)
    }
}
