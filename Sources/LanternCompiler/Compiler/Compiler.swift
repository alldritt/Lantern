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
    private var compilingMethodOfType: String? = nil
    /// Outer scope locals available for capture (set during closure compilation)
    private var outerLocals: [ScopeTracker.Local] = []
    /// Captured variable names in order (built during closure body compilation)
    private var capturedNames: [String] = []

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

        // Second pass: compile declarations first (hoisting)
        for statement in ast.statements {
            if statement is FunctionDeclarationNode || statement is StructDeclarationNode ||
               statement is ClassDeclarationNode || statement is EnumDeclarationNode ||
               statement is ExtensionNode {
                compileStatement(statement)
            }
        }

        // Third pass: compile remaining statements
        for statement in ast.statements {
            if !(statement is FunctionDeclarationNode || statement is StructDeclarationNode ||
                 statement is ClassDeclarationNode || statement is EnumDeclarationNode ||
                 statement is ExtensionNode) {
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
                symbolTable.register(varDecl.name, kind: .global(isMutable: varDecl.isMutable), location: varDecl.location)
            }
        }
    }

    // MARK: - Statement Compilation

    private func compileStatement(_ stmt: StatementNode) {
        if let varDecl = stmt as? VariableDeclarationNode {
            compileVariableDeclaration(varDecl)
        } else if let exprStmt = stmt as? ExpressionStatementNode {
            // Check for mutating method calls that need store-back
            if let call = exprStmt.expression as? FunctionCallNode,
               let memberAccess = call.callee as? MemberAccessNode,
               isMutatingMethod(memberAccess.member) {
                // Compile the method call
                compileExpression(exprStmt.expression)
                // Store the result back to the receiver variable
                if let receiver = memberAccess.object as? IdentifierNode {
                    if let local = scopeTracker.resolve(receiver.name) {
                        Instruction.storeLocal(local.slot, into: &chunk)
                    } else if compilingMethodOfType != nil && symbolTable.lookup(receiver.name) == nil && !isKnownGlobal(receiver.name) {
                        // Implicit self.property — store back via setProperty
                        // Stack has: [modifiedValue]. Need: [self, modifiedValue]
                        // So push self UNDER the value: swap by storing value, pushing self, pushing value
                        let tempSlot = scopeTracker.declare(name: "__storeback_temp", isMutable: true)
                        Instruction.storeLocal(tempSlot, into: &chunk) // save modified value
                        if let selfLocal = scopeTracker.resolve("self") {
                            Instruction.loadLocal(selfLocal.slot, into: &chunk)
                        } else {
                            Instruction.loadLocal(0, into: &chunk)
                        }
                        Instruction.loadLocal(tempSlot, into: &chunk) // restore modified value on top
                        let nameIndex = chunk.constantPool.addPropertyName(receiver.name)
                        Instruction.setProperty(nameIndex, into: &chunk)
                    } else {
                        let nameIndex = chunk.constantPool.addString(receiver.name)
                        Instruction.storeGlobal(nameIndex, into: &chunk)
                    }
                } else if let propAccess = memberAccess.object as? MemberAccessNode {
                    // Stack: [modifiedValue]. Need [object, modifiedValue]
                    let tempSlot2 = scopeTracker.declare(name: "__chain_temp", isMutable: true)
                    Instruction.storeLocal(tempSlot2, into: &chunk)
                    compileExpression(propAccess.object)
                    Instruction.loadLocal(tempSlot2, into: &chunk)
                    let nameIndex = chunk.constantPool.addPropertyName(propAccess.member)
                    Instruction.setProperty(nameIndex, into: &chunk)
                    // For struct value semantics, also store the object back
                    if let objIdent = propAccess.object as? IdentifierNode {
                        // Reload modified object and store back
                        compileExpression(propAccess.object)
                        if let local = scopeTracker.resolve(objIdent.name) {
                            Instruction.storeLocal(local.slot, into: &chunk)
                        } else {
                            let ni = chunk.constantPool.addString(objIdent.name)
                            Instruction.storeGlobal(ni, into: &chunk)
                        }
                    }
                } else {
                    chunk.write(.pop)
                }
            } else {
                compileExpression(exprStmt.expression)
                chunk.write(.pop)
            }
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
            // Wrap in optional if type annotation indicates optional
            if let type = decl.typeAnnotation, type.hasSuffix("?") {
                // Only wrap if the value isn't already nil
                // nil doesn't need wrapping
                if !(initializer is NilLiteralNode) {
                    chunk.write(.wrapOptional)
                }
            }
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
            let hasInit = decl.initializer != nil
            let slot = scopeTracker.declare(name: decl.name, isMutable: decl.isMutable, typeAnnotation: decl.typeAnnotation, isInitialized: hasInit)
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

        // Continue target: jump here to do increment then re-check
        let continueTarget = chunk.count

        // Increment loop variable
        Instruction.loadLocal(varSlot, into: &chunk)
        Instruction.constInt(1, into: &chunk)
        chunk.write(.add)
        Instruction.storeLocal(varSlot, into: &chunk)

        // Loop back to condition
        chunk.write(.loop)
        chunk.writeI16(Int16(loopStart - (chunk.count + 2)))

        Instruction.patchJump(at: exitJump, in: &chunk)

        for bp in breakTargets { Instruction.patchJump(at: bp, in: &chunk) }
        for cp in continueTargets { chunk.patchI16(at: cp, value: Int16(continueTarget - (cp + 2))) }

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

        // Check for tuple destructuring pattern like (index, value)
        let varName = stmt.variableName.trimmingCharacters(in: .whitespaces)
        if varName.hasPrefix("(") && varName.hasSuffix(")") {
            // Tuple destructuring: "(a, b)" -> extract elements
            let inner = String(varName.dropFirst().dropLast())
            let parts = inner.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            let tupleSlot = scopeTracker.declare(name: "__tuple", isMutable: false)
            Instruction.storeLocal(tupleSlot, into: &chunk)
            for (i, part) in parts.enumerated() {
                if part != "_" {
                    Instruction.loadLocal(tupleSlot, into: &chunk)
                    Instruction.constInt(i, into: &chunk)
                    chunk.write(.getIndex)
                    let partSlot = scopeTracker.declare(name: part, isMutable: false)
                    Instruction.storeLocal(partSlot, into: &chunk)
                }
            }
        } else {
            let varSlot = scopeTracker.declare(name: stmt.variableName, isMutable: false)
            Instruction.storeLocal(varSlot, into: &chunk)
        }

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

        // Push error handler — offset will be patched to point to catch block
        let handlerPatch = Instruction.pushHandler(into: &chunk)

        // Compile do body
        compileBlock(stmt.body)

        // No error: pop handler and jump past catch blocks
        chunk.write(.popHandler)
        let jumpEnd = Instruction.jump(into: &chunk)

        // Patch handler to jump here (start of catch blocks)
        Instruction.patchJump(at: handlerPatch, in: &chunk)

        // The thrown error value is on the stack at this point
        // Compile catch clauses with pattern matching
        var catchEndJumps: [Int] = []

        for clause in stmt.catchClauses {
            if let pattern = clause.pattern {
                // Specific catch pattern — try to match against the error
                chunk.write(.dup) // dup error for comparison
                // Try to compile the pattern as an expression (e.g., enum case reference)
                if let patternExpr = parsePatternAsExpression(pattern) {
                    compileExpression(patternExpr)
                } else {
                    Instruction.constString(pattern, into: &chunk)
                }
                chunk.write(.eq)
                let skipCatch = Instruction.jumpIfFalse(into: &chunk)

                // Match: pop error, execute catch body, jump to end
                scopeTracker.pushScope()
                let slot = scopeTracker.declare(name: "error", isMutable: false)
                chunk.write(.dup)
                Instruction.storeLocal(slot, into: &chunk)
                chunk.write(.pop) // pop the error from main stack
                compileBlock(clause.body)
                _ = scopeTracker.popScope()
                let endJump = Instruction.jump(into: &chunk)
                catchEndJumps.append(endJump)

                Instruction.patchJump(at: skipCatch, in: &chunk)
            } else {
                // catch-all: always matches — pop error, execute body
                scopeTracker.pushScope()
                let slot = scopeTracker.declare(name: "error", isMutable: false)
                chunk.write(.dup)
                Instruction.storeLocal(slot, into: &chunk)
                chunk.write(.pop) // pop error from main stack
                compileBlock(clause.body)
                _ = scopeTracker.popScope()
                let endJump = Instruction.jump(into: &chunk)
                catchEndJumps.append(endJump)
            }
        }

        // If no catch matched, pop the error
        chunk.write(.pop)

        for ej in catchEndJumps {
            Instruction.patchJump(at: ej, in: &chunk)
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
                        // Handle implicit member access patterns like `.north` in switch
                        if let member = expr as? MemberAccessNode, member.object is SelfNode {
                            // Try to find the enum type by checking all registered enum types
                            var found = false
                            for typeInfo in typeDebugInfo where typeInfo.kind == .enum {
                                if typeInfo.properties.contains(where: { $0.name == member.member }) {
                                    let qualifiedName = "\(typeInfo.name).\(member.member)"
                                    let nameIndex = chunk.constantPool.addString(qualifiedName)
                                    Instruction.loadGlobal(nameIndex, into: &chunk)
                                    found = true
                                    break
                                }
                            }
                            if !found { compileExpression(expr) }
                        } else {
                            compileExpression(expr)
                        }
                    case .identifier(let name):
                        Instruction.constString(name, into: &chunk)
                    case .wildcard:
                        Instruction.constBool(true, into: &chunk)
                        let jump = Instruction.jumpIfTrue(into: &chunk)
                        caseJumps.append(jump)
                        continue
                    case .enumCase(let caseName, let bindings):
                        // Compare subject's caseName
                        let caseNameIdx = chunk.constantPool.addPropertyName("caseName")
                        Instruction.getProperty(caseNameIdx, into: &chunk) // gets caseName string from dup'd subject
                        Instruction.constString(caseName, into: &chunk)
                        chunk.write(.eq)
                        let jump = Instruction.jumpIfTrue(into: &chunk)
                        caseJumps.append(jump)
                        continue // bindings extracted below after match confirmed
                    }
                    chunk.write(.eq)
                    let jump = Instruction.jumpIfTrue(into: &chunk)
                    caseJumps.append(jump)
                }

                let nextCase = Instruction.jump(into: &chunk)

                for cj in caseJumps {
                    Instruction.patchJump(at: cj, in: &chunk)
                }

                // Extract enum bindings if this is an enumCase pattern
                let enumBindings = switchCase.patterns.compactMap { p -> (String, [String])? in
                    if case .enumCase(let cn, let binds) = p { return (cn, binds) }
                    return nil
                }.first

                if let (_, bindings) = enumBindings, !bindings.isEmpty {
                    // Subject is still on stack — save it and extract associated values
                    scopeTracker.pushScope()
                    // Save subject to a temp local
                    let subjectSlot = scopeTracker.declare(name: "__switch_subject", isMutable: false)
                    chunk.write(.dup)
                    Instruction.storeLocal(subjectSlot, into: &chunk)

                    // Get the associatedValues array once
                    let assocIdx = chunk.constantPool.addPropertyName("associatedValues")
                    Instruction.loadLocal(subjectSlot, into: &chunk)
                    Instruction.getProperty(assocIdx, into: &chunk)
                    let arrSlot = scopeTracker.declare(name: "__assoc_values", isMutable: false)
                    Instruction.storeLocal(arrSlot, into: &chunk)

                    // Extract each binding from the array
                    for (i, binding) in bindings.enumerated() {
                        Instruction.loadLocal(arrSlot, into: &chunk)
                        Instruction.constInt(i, into: &chunk)
                        chunk.write(.getIndex)
                        let slot = scopeTracker.declare(name: binding, isMutable: false)
                        Instruction.storeLocal(slot, into: &chunk)
                    }

                    chunk.write(.pop) // Pop the subject
                    compileBlock(switchCase.body)
                    let removed = scopeTracker.popScope()
                    for _ in removed { chunk.write(.pop) }
                } else {
                    chunk.write(.pop) // Pop the subject
                    compileBlock(switchCase.body)
                }
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

        // Set up capture tracking for nested functions
        let savedOuterLocals = outerLocals
        let savedCapturedNames = capturedNames
        var allOuterLocalsForFunc: [ScopeTracker.Local] = []
        for name in scopeTracker.allLocalNames() {
            if let local = scopeTracker.resolve(name) { allOuterLocalsForFunc.append(local) }
        }
        outerLocals = allOuterLocalsForFunc
        capturedNames = []

        // Jump over the function body (it's inlined in the shared bytecode)
        let jumpOver = Instruction.jump(into: &chunk)
        let bodyStart = chunk.count

        // Compile function body inline — each function has its own slot space
        let savedFullState = scopeTracker.saveFullState()
        scopeTracker.restoreFullState(([], 0, 0))
        scopeTracker.pushScope()
        for param in decl.parameters {
            scopeTracker.declare(name: param.internalName, isMutable: false, typeAnnotation: param.typeAnnotation)
        }

        // Emit default value handling for parameters with defaults
        for (i, param) in decl.parameters.enumerated() {
            if let defaultExpr = param.defaultValue {
                // If the parameter is nil (not provided), use the default value
                Instruction.loadLocal(UInt16(i), into: &chunk)
                chunk.write(.dup)
                let jumpHasValue = Instruction.jumpIfTrue(into: &chunk)
                chunk.write(.pop) // pop the nil
                compileExpression(defaultExpr) // push default value
                Instruction.storeLocal(UInt16(i), into: &chunk)
                let jumpEnd = Instruction.jump(into: &chunk)
                Instruction.patchJump(at: jumpHasValue, in: &chunk)
                chunk.write(.pop) // pop the dup'd value (it was non-nil)
                Instruction.patchJump(at: jumpEnd, in: &chunk)
            }
        }

        for stmt in decl.body.statements {
            compileStatement(stmt)
        }

        // Implicit return void if last instruction is not a return
        if chunk.bytecode.isEmpty || chunk.bytecode.last != Opcode.return_.rawValue {
            chunk.write(.returnVoid)
        }

        _ = scopeTracker.popScope()
        scopeTracker.restoreFullState(savedFullState)

        let bodyEnd = chunk.count
        Instruction.patchJump(at: jumpOver, in: &chunk)

        let funcCaptureCount = capturedNames.count

        // Push captured values in REVERSE order
        for captureName in capturedNames.reversed() {
            if let outerLocal = allOuterLocalsForFunc.first(where: { $0.name == captureName }) {
                Instruction.loadLocal(outerLocal.slot, into: &chunk)
            } else {
                let ni = chunk.constantPool.addString(captureName)
                Instruction.loadGlobal(ni, into: &chunk)
            }
        }

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
            bytecode: [],
            bytecodeOffset: bodyStart
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
        chunk.write(UInt8(funcCaptureCount))
        Instruction.storeGlobal(nameIndex, into: &chunk)

        // Restore capture state
        outerLocals = savedOuterLocals
        capturedNames = savedCapturedNames
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
            } else if let prop = member as? PropertyNode, !prop.isStatic {
                properties.append(PropertyInfo(
                    name: prop.name,
                    typeAnnotation: prop.typeAnnotation,
                    isMutable: prop.isMutable
                ))
                }
        }

        // Compile methods and computed properties
        for member in decl.members {
            if let funcDecl = member as? FunctionDeclarationNode {
                if funcDecl.isStatic {
                    compileStaticMethod(funcDecl, typeName: decl.name)
                } else {
                    compileTypeMethod(funcDecl, typeName: decl.name)
                }
            } else if let computed = member as? ComputedPropertyNode {
                compileComputedProperty(computed, typeName: decl.name)
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

        // Check for custom init
        let structInits = decl.members.compactMap { $0 as? InitializerNode }
        if let customInit = structInits.first {
            compileCustomInit(customInit, typeName: decl.name, typeIndex: typeIndex, propNames: properties.map(\.name), kind: .struct)
        } else {
            var defaults: [ExpressionNode?] = []
            for member in decl.members {
                if let prop = member as? VariableDeclarationNode { defaults.append(prop.initializer) }
                else if let prop = member as? PropertyNode { defaults.append(prop.initializer) }
            }
            emitMemberwiseInit(name: decl.name, typeIndex: typeIndex, propNames: properties.map(\.name), defaults: defaults, kind: .struct)
        }

        // Compile static stored properties AFTER the constructor is available
        for member in decl.members {
            if let prop = member as? PropertyNode, prop.isStatic, let initializer = prop.initializer {
                compileExpression(initializer)
                let nameIndex = chunk.constantPool.addString("\(decl.name).\(prop.name)")
                Instruction.storeGlobal(nameIndex, into: &chunk)
            }
        }
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
            } else if let prop = member as? PropertyNode {
                properties.append(PropertyInfo(
                    name: prop.name,
                    typeAnnotation: prop.typeAnnotation,
                    isMutable: prop.isMutable
                ))
            }
        }

        // Compile methods and computed properties
        for member in decl.members {
            if let funcDecl = member as? FunctionDeclarationNode {
                if funcDecl.isStatic {
                    compileStaticMethod(funcDecl, typeName: decl.name)
                } else {
                    compileTypeMethod(funcDecl, typeName: decl.name)
                }
            } else if let computed = member as? ComputedPropertyNode {
                compileComputedProperty(computed, typeName: decl.name)
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

        // Check for custom init
        let customInits = decl.members.compactMap { $0 as? InitializerNode }
        if let customInit = customInits.first {
            compileCustomInit(customInit, typeName: decl.name, typeIndex: typeIndex, propNames: properties.map(\.name), kind: .class)
        } else {
            var classDefaults: [ExpressionNode?] = []
            for member in decl.members {
                if let prop = member as? VariableDeclarationNode { classDefaults.append(prop.initializer) }
                else if let prop = member as? PropertyNode { classDefaults.append(prop.initializer) }
            }
            emitMemberwiseInit(name: decl.name, typeIndex: typeIndex, propNames: properties.map(\.name), defaults: classDefaults, kind: .class)
        }

        // Compile static stored properties (class)
        for member in decl.members {
            if let prop = member as? PropertyNode, prop.isStatic, let initializer = prop.initializer {
                compileExpression(initializer)
                let nameIndex = chunk.constantPool.addString("\(decl.name).\(prop.name)")
                Instruction.storeGlobal(nameIndex, into: &chunk)
            }
        }
    }

    /// Compile a method as a global function "TypeName.methodName" with implicit self parameter
    private func compileTypeMethod(_ decl: FunctionDeclarationNode, typeName: String) {
        let qualifiedName = "\(typeName).\(decl.name)"

        let jumpOver = Instruction.jump(into: &chunk)
        let bodyStart = chunk.count

        let savedSlots = scopeTracker.saveSlotState()
        scopeTracker.restoreSlotState(0)
        scopeTracker.pushScope()

        // Slot 0 = self (implicit)
        scopeTracker.declare(name: "self", isMutable: false)
        for param in decl.parameters {
            scopeTracker.declare(name: param.internalName, isMutable: false, typeAnnotation: param.typeAnnotation)
        }

        let savedCompilingMethod = compilingMethodOfType
        compilingMethodOfType = typeName

        for stmt in decl.body.statements {
            compileStatement(stmt)
        }

        compilingMethodOfType = savedCompilingMethod

        if chunk.bytecode.isEmpty || chunk.bytecode.last != Opcode.return_.rawValue {
            chunk.write(.returnVoid)
        }

        _ = scopeTracker.popScope()
        compilingMethodOfType = savedCompilingMethod
        scopeTracker.restoreSlotState(savedSlots)

        let bodyEnd = chunk.count
        Instruction.patchJump(at: jumpOver, in: &chunk)

        var params = [ParameterInfo(label: nil, name: "self")]
        params += decl.parameters.map { ParameterInfo(label: $0.externalName, name: $0.internalName, typeAnnotation: $0.typeAnnotation) }

        let funcRef = FunctionRef(name: qualifiedName, parameters: params, localCount: UInt16(params.count + 16), bytecode: [], bytecodeOffset: bodyStart)
        let funcIndex = chunk.constantPool.addFunction(funcRef)

        functionDebugInfo.append(FunctionDebugInfo(
            name: qualifiedName,
            parameterNames: params.map(\.name),
            sourceRange: (start: decl.location, end: decl.location),
            bytecodeRange: (start: bodyStart, end: bodyEnd)
        ))

        let nameIndex = chunk.constantPool.addString(qualifiedName)
        chunk.write(.closure)
        chunk.writeU16(funcIndex)
        chunk.write(0)
        Instruction.storeGlobal(nameIndex, into: &chunk)
    }

    /// Generate a memberwise initializer stored as a global
    /// Compile a static method as "TypeName.methodName" (no self parameter).
    private func compileStaticMethod(_ decl: FunctionDeclarationNode, typeName: String) {
        let qualifiedName = "\(typeName).\(decl.name)"

        let jumpOver = Instruction.jump(into: &chunk)
        let bodyStart = chunk.count

        let savedSlots = scopeTracker.saveSlotState()
        scopeTracker.restoreSlotState(0)
        scopeTracker.pushScope()

        // No self parameter for static methods
        for param in decl.parameters {
            scopeTracker.declare(name: param.internalName, isMutable: false, typeAnnotation: param.typeAnnotation)
        }

        for stmt in decl.body.statements {
            compileStatement(stmt)
        }

        if chunk.bytecode.isEmpty || chunk.bytecode.last != Opcode.return_.rawValue {
            chunk.write(.returnVoid)
        }

        _ = scopeTracker.popScope()
        scopeTracker.restoreSlotState(savedSlots)

        let bodyEnd = chunk.count
        Instruction.patchJump(at: jumpOver, in: &chunk)

        let params = decl.parameters.map {
            ParameterInfo(label: $0.externalName, name: $0.internalName, typeAnnotation: $0.typeAnnotation)
        }

        let funcRef = FunctionRef(name: qualifiedName, parameters: params, localCount: UInt16(params.count + 16), bytecode: [], bytecodeOffset: bodyStart)
        let funcIndex = chunk.constantPool.addFunction(funcRef)

        functionDebugInfo.append(FunctionDebugInfo(
            name: qualifiedName,
            parameterNames: params.map(\.name),
            sourceRange: (start: decl.location, end: decl.location),
            bytecodeRange: (start: bodyStart, end: bodyEnd)
        ))

        let nameIndex = chunk.constantPool.addString(qualifiedName)
        chunk.write(.closure)
        chunk.writeU16(funcIndex)
        chunk.write(0)
        Instruction.storeGlobal(nameIndex, into: &chunk)
    }

    /// Compile a computed property getter (and optionally setter) as methods.
    private func compileComputedProperty(_ prop: ComputedPropertyNode, typeName: String) {
        compileComputedPropertyDirect(prop, typeName: typeName)
    }

    private func compileComputedPropertyDirect(_ prop: ComputedPropertyNode, typeName: String) {
        let getterName = "\(typeName).__get_\(prop.name)"

        let jumpOver = Instruction.jump(into: &chunk)
        let bodyStart = chunk.count

        let savedSlots = scopeTracker.saveSlotState()
        scopeTracker.restoreSlotState(0)
        let savedMethod = compilingMethodOfType
        compilingMethodOfType = typeName
        scopeTracker.pushScope()
        scopeTracker.declare(name: "self", isMutable: false)

        for stmt in prop.getter.statements {
            compileStatement(stmt)
        }

        if chunk.bytecode.isEmpty || chunk.bytecode.last != Opcode.return_.rawValue {
            chunk.write(.returnVoid)
        }

        _ = scopeTracker.popScope()
        compilingMethodOfType = savedMethod
        scopeTracker.restoreSlotState(savedSlots)

        let bodyEnd = chunk.count
        Instruction.patchJump(at: jumpOver, in: &chunk)

        let funcRef = FunctionRef(
            name: getterName,
            parameters: [ParameterInfo(name: "self")],
            localCount: UInt16(1 + 16),
            bytecode: [],
            bytecodeOffset: bodyStart
        )
        let funcIndex = chunk.constantPool.addFunction(funcRef)

        functionDebugInfo.append(FunctionDebugInfo(
            name: getterName,
            parameterNames: ["self"],
            sourceRange: (start: prop.location, end: prop.location),
            bytecodeRange: (start: bodyStart, end: bodyEnd)
        ))

        let nameIndex = chunk.constantPool.addString(getterName)
        chunk.write(.closure)
        chunk.writeU16(funcIndex)
        chunk.write(0)
        Instruction.storeGlobal(nameIndex, into: &chunk)

        // Compile setter if present
        if let setter = prop.setter {
            let setterName = "\(typeName).__set_\(prop.name)"
            let setJumpOver = Instruction.jump(into: &chunk)
            let setBodyStart = chunk.count

            let setSavedSlots = scopeTracker.saveSlotState()
            scopeTracker.restoreSlotState(0)
            let setSavedMethod = compilingMethodOfType
            compilingMethodOfType = typeName
            scopeTracker.pushScope()
            scopeTracker.declare(name: "self", isMutable: true)
            scopeTracker.declare(name: "newValue", isMutable: false)

            for stmt in setter.statements {
                compileStatement(stmt)
            }

            // Return self (modified)
            if let selfLocal = scopeTracker.resolve("self") {
                Instruction.loadLocal(selfLocal.slot, into: &chunk)
            } else {
                Instruction.loadLocal(0, into: &chunk)
            }
            chunk.write(.return_)

            _ = scopeTracker.popScope()
            compilingMethodOfType = setSavedMethod
            scopeTracker.restoreSlotState(setSavedSlots)

            let setBodyEnd = chunk.count
            Instruction.patchJump(at: setJumpOver, in: &chunk)

            let setFuncRef = FunctionRef(
                name: setterName,
                parameters: [ParameterInfo(name: "self"), ParameterInfo(name: "newValue")],
                localCount: UInt16(2 + 16),
                bytecode: [],
                bytecodeOffset: setBodyStart
            )
            let setFuncIndex = chunk.constantPool.addFunction(setFuncRef)

            functionDebugInfo.append(FunctionDebugInfo(
                name: setterName,
                parameterNames: ["self", "newValue"],
                sourceRange: (start: prop.location, end: prop.location),
                bytecodeRange: (start: setBodyStart, end: setBodyEnd)
            ))

            let setNameIndex = chunk.constantPool.addString(setterName)
            chunk.write(.closure)
            chunk.writeU16(setFuncIndex)
            chunk.write(0)
            Instruction.storeGlobal(setNameIndex, into: &chunk)
        }
    }

    /// Compile a custom init declaration as the type's constructor.
    /// init(params) { self.prop = param; ... } becomes a function that creates
    /// an empty instance, runs the body (with self at slot 0), and returns self.
    private func compileCustomInit(_ initNode: InitializerNode, typeName: String, typeIndex: UInt16, propNames: [String], kind: TypeKind) {
        let jumpOver = Instruction.jump(into: &chunk)
        let bodyStart = chunk.count

        let savedSlots = scopeTracker.saveSlotState()
        scopeTracker.restoreSlotState(0)
        let savedMethod = compilingMethodOfType
        compilingMethodOfType = typeName
        scopeTracker.pushScope()

        // Slots 0..N-1 are the init parameters (from caller)
        for param in initNode.parameters {
            scopeTracker.declare(name: param.internalName, isMutable: false, typeAnnotation: param.typeAnnotation)
        }

        // Create empty instance and store in 'self' (next slot after params)
        for _ in propNames { chunk.write(.constNil) }
        Instruction.construct(typeIndex, argCount: UInt8(propNames.count), into: &chunk)
        let selfSlot = scopeTracker.declare(name: "self", isMutable: true)
        Instruction.storeLocal(selfSlot, into: &chunk)

        // Compile init body (assignments like self.name = name)
        for stmt in initNode.body.statements {
            compileStatement(stmt)
        }

        // Return self
        Instruction.loadLocal(selfSlot, into: &chunk)
        chunk.write(.return_)

        _ = scopeTracker.popScope()
        compilingMethodOfType = savedMethod
        scopeTracker.restoreSlotState(savedSlots)

        let bodyEnd = chunk.count
        Instruction.patchJump(at: jumpOver, in: &chunk)

        // The init function takes the same params as the init declaration
        // But slot 0 is self (not a parameter from the caller)
        // The caller pushes args for params only, and self is created internally
        // So the function's parameter list matches initNode.parameters
        var params = initNode.parameters.map {
            ParameterInfo(label: $0.externalName, name: $0.internalName, typeAnnotation: $0.typeAnnotation)
        }

        // localCount = 1 (self) + params.count + extra
        let funcRef = FunctionRef(
            name: typeName,
            parameters: params,
            localCount: UInt16(1 + params.count + 16),
            bytecode: [],
            bytecodeOffset: bodyStart
        )
        let funcIndex = chunk.constantPool.addFunction(funcRef)

        functionDebugInfo.append(FunctionDebugInfo(
            name: typeName,
            parameterNames: params.map(\.name),
            sourceRange: (start: initNode.location, end: initNode.location),
            bytecodeRange: (start: bodyStart, end: bodyEnd)
        ))

        let nameIndex = chunk.constantPool.addString(typeName)
        chunk.write(.closure)
        chunk.writeU16(funcIndex)
        chunk.write(0)
        Instruction.storeGlobal(nameIndex, into: &chunk)
    }

    private func emitMemberwiseInit(name: String, typeIndex: UInt16, propNames: [String], defaults: [ExpressionNode?] = [], kind: TypeKind) {
        let jumpOver = Instruction.jump(into: &chunk)
        let bodyStart = chunk.count

        let savedSlots = scopeTracker.saveSlotState()
        scopeTracker.restoreSlotState(0)
        scopeTracker.pushScope()
        for prop in propNames {
            scopeTracker.declare(name: prop, isMutable: false)
        }

        for (i, _) in propNames.enumerated() {
            Instruction.loadLocal(UInt16(i), into: &chunk)
            // If property has a default value, use nil-coalescing: param ?? default
            if i < defaults.count, let defaultExpr = defaults[i] {
                chunk.write(.dup)
                let jumpHasValue = Instruction.jumpIfTrue(into: &chunk)
                chunk.write(.pop) // pop the nil
                compileExpression(defaultExpr) // push the default value
                Instruction.patchJump(at: jumpHasValue, in: &chunk)
            }
        }
        Instruction.construct(typeIndex, argCount: UInt8(propNames.count), into: &chunk)
        chunk.write(.return_)

        _ = scopeTracker.popScope()
        scopeTracker.restoreSlotState(savedSlots)

        let bodyEnd = chunk.count
        Instruction.patchJump(at: jumpOver, in: &chunk)

        let initParams = propNames.map { ParameterInfo(label: $0, name: $0) }
        let initRef = FunctionRef(name: name, parameters: initParams, localCount: UInt16(propNames.count + 4), bytecode: [], bytecodeOffset: bodyStart)
        let funcIndex = chunk.constantPool.addFunction(initRef)

        functionDebugInfo.append(FunctionDebugInfo(
            name: name,
            parameterNames: propNames,
            sourceRange: (start: .unknown, end: .unknown),
            bytecodeRange: (start: bodyStart, end: bodyEnd)
        ))

        let nameIndex = chunk.constantPool.addString(name)
        chunk.write(.closure)
        chunk.writeU16(funcIndex)
        chunk.write(0)
        Instruction.storeGlobal(nameIndex, into: &chunk)
    }

    private func compileEnumDeclaration(_ decl: EnumDeclarationNode) {
        emitLocation(decl.location)
        let typeIndex = chunk.constantPool.addTypeName(decl.name)

        // Store enum case names in the constant pool so the interpreter can register them
        // We use properties in the TypeDebugInfo to carry case names (for enum kind)
        // The interpreter reads these and creates EnumCaseRef globals

        // Compile methods and computed properties
        for member in decl.members {
            if let funcDecl = member as? FunctionDeclarationNode {
                if funcDecl.isStatic {
                    compileStaticMethod(funcDecl, typeName: decl.name)
                } else {
                    compileTypeMethod(funcDecl, typeName: decl.name)
                }
            } else if let computed = member as? ComputedPropertyNode {
                compileComputedProperty(computed, typeName: decl.name)
            }
        }

        // For enums, store case names as properties
        // Use typeAnnotation to carry explicit raw values
        var nextIntRaw = 0
        let caseInfos = decl.cases.map { enumCase -> PropertyInfo in
            var rawAnnotation: String? = nil
            if let rawExpr = enumCase.rawValue {
                if let intLit = rawExpr as? IntLiteralNode {
                    rawAnnotation = "\(intLit.value)"
                    nextIntRaw = intLit.value + 1
                } else if let strLit = rawExpr as? StringLiteralNode {
                    rawAnnotation = "\"\(strLit.value)\""
                }
            } else if decl.conformances.contains("Int") {
                rawAnnotation = "\(nextIntRaw)"
                nextIntRaw += 1
            }
            let hasAssocValues = enumCase.associatedValues != nil && !(enumCase.associatedValues?.isEmpty ?? true)
            return PropertyInfo(name: enumCase.name, typeAnnotation: rawAnnotation, isMutable: false, isComputed: hasAssocValues)
        }
        typeDebugInfo.append(TypeDebugInfo(
            name: decl.name,
            kind: .enum,
            properties: caseInfos,
            methods: decl.members.compactMap { ($0 as? FunctionDeclarationNode)?.name },
            conformances: decl.conformances,
            sourceRange: (start: decl.location, end: decl.location)
        ))
        _ = typeIndex
    }

    private func compileExtension(_ ext: ExtensionNode) {
        let typeName = ext.typeName
        for member in ext.members {
            if let funcDecl = member as? FunctionDeclarationNode {
                compileTypeMethod(funcDecl, typeName: typeName)
            } else if let computed = member as? ComputedPropertyNode {
                compileComputedProperty(computed, typeName: typeName)
            } else {
                compileStatement(member)
            }
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
            // Check if this is a type member access (e.g., Direction.north)
            if let ident = member.object as? IdentifierNode,
               symbolTable.lookup(ident.name)?.isType == true {
                // Qualified name: "TypeName.member"
                let qualifiedName = "\(ident.name).\(member.member)"
                let nameIndex = chunk.constantPool.addString(qualifiedName)
                Instruction.loadGlobal(nameIndex, into: &chunk)
            } else if member.object is SelfNode,
                      case .enumCase(let typeName) = symbolTable.lookup(member.member)?.kind {
                // Implicit member access like `.north` resolving to enum case
                let qualifiedName = "\(typeName).\(member.member)"
                let nameIndex = chunk.constantPool.addString(qualifiedName)
                Instruction.loadGlobal(nameIndex, into: &chunk)
            } else {
                compileExpression(member.object)
                let nameIndex = chunk.constantPool.addPropertyName(member.member)
                Instruction.getProperty(nameIndex, into: &chunk)
            }
        } else if expr is SelfNode {
            // self is at slot 0 in methods, or at the declared slot in custom inits
            if let resolved = scopeTracker.resolve("self") {
                Instruction.loadLocal(resolved.slot, into: &chunk)
            } else {
                Instruction.loadLocal(0, into: &chunk)
            }
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
            if tryExpr.kind == .tryOptional {
                // try? — catch errors and return nil
                let handlerPatch = Instruction.pushHandler(into: &chunk)
                compileExpression(tryExpr.expression)
                chunk.write(.wrapOptional)
                chunk.write(.popHandler)
                let jumpEnd = Instruction.jump(into: &chunk)
                // Handler: error occurred — push nil
                Instruction.patchJump(at: handlerPatch, in: &chunk)
                chunk.write(.pop) // pop error
                chunk.write(.constNil)
                Instruction.patchJump(at: jumpEnd, in: &chunk)
            } else {
                compileExpression(tryExpr.expression)
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

    /// Known builtin names that should NOT be treated as implicit self.property
    private static let knownBuiltins: Set<String> = [
        "print", "debugPrint", "String", "Int", "Double", "Bool", "Array",
        "abs", "min", "max", "type", "zip", "+", "*"
    ]

    private static let mutatingMethods: Set<String> = [
        "append", "remove", "removeLast", "removeAll", "removeValue",
        "insert", "sort", "reverse", "shuffle", "swapAt"
    ]

    private func isMutatingMethod(_ name: String) -> Bool {
        Self.mutatingMethods.contains(name)
    }

    private func isKnownGlobal(_ name: String) -> Bool {
        Self.knownBuiltins.contains(name)
    }

    private func compileIdentifier(_ ident: IdentifierNode) {
        // Check locals first (inner to outer scope)
        if let local = scopeTracker.resolve(ident.name) {
            Instruction.loadLocal(local.slot, into: &chunk)
        } else if !outerLocals.isEmpty, let outerLocal = outerLocals.first(where: { $0.name == ident.name }) {
            // Captured variable from enclosing scope
            if let captureIdx = capturedNames.firstIndex(of: ident.name) {
                chunk.write(.loadCapture)
                chunk.writeU16(UInt16(captureIdx))
            } else {
                capturedNames.append(ident.name)
                chunk.write(.loadCapture)
                chunk.writeU16(UInt16(capturedNames.count - 1))
            }
            _ = outerLocal // suppress warning
        } else if compilingMethodOfType != nil
                    && symbolTable.lookup(ident.name) == nil
                    && !isKnownGlobal(ident.name) {
            // Inside a type method body — truly unresolved identifiers are implicit self.property
            // Inside a type method body — unresolved identifiers are implicit self.property
            if let selfLocal = scopeTracker.resolve("self") {
                Instruction.loadLocal(selfLocal.slot, into: &chunk)
            } else {
                Instruction.loadLocal(0, into: &chunk)
            }
            let nameIndex = chunk.constantPool.addPropertyName(ident.name)
            Instruction.getProperty(nameIndex, into: &chunk)
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
            compileExpression(binary.right)
            chunk.write(.nilCoalesce) // VM handles unwrap-or-fallback
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
        case .identityEqual: chunk.write(.eq) // For InstanceRef (class), eq checks identity
        case .identityNotEqual: chunk.write(.neq)
        default:
            diagnosticEngine.warning("Operator \(binary.op.rawValue) not fully implemented", at: binary.location)
            chunk.write(.add)
        }
    }

    private func compileFunctionCall(_ call: FunctionCallNode) {
        // Check if it's a method call
        if let memberAccess = call.callee as? MemberAccessNode {
            // Check if the object is a type name — if so, call as qualified function
            if let ident = memberAccess.object as? IdentifierNode,
               symbolTable.lookup(ident.name)?.isType == true {
                // Type.method() or Type.enumCase() — compile as loadGlobal("Type.method") + call
                let qualifiedName = "\(ident.name).\(memberAccess.member)"
                let nameIndex = chunk.constantPool.addString(qualifiedName)
                Instruction.loadGlobal(nameIndex, into: &chunk)
                for arg in call.arguments { compileExpression(arg.value) }
                Instruction.call(argCount: UInt8(call.arguments.count), into: &chunk)
            } else {
                compileExpression(memberAccess.object)
                for arg in call.arguments { compileExpression(arg.value) }
                let nameIndex = chunk.constantPool.addMethodName(memberAccess.member)
                Instruction.callMethod(nameIndex, argCount: UInt8(call.arguments.count), into: &chunk)
            }
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

        // Save outer scope locals for capture detection
        let savedOuterLocals = outerLocals
        let savedCapturedNames = capturedNames

        // Collect all current locals as potential captures
        var allOuterLocals: [ScopeTracker.Local] = []
        // Get current scope locals before resetting
        for name in scopeTracker.allLocalNames() {
            if let local = scopeTracker.resolve(name) {
                allOuterLocals.append(local)
            }
        }
        outerLocals = allOuterLocals
        capturedNames = []

        // Jump over the closure body
        let jumpOver = Instruction.jump(into: &chunk)
        let bodyStart = chunk.count

        // Save FULL scope state and clear — closure has its own scope
        let savedFullState = scopeTracker.saveFullState()
        scopeTracker.restoreFullState(([], 0, 0))
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
        scopeTracker.restoreFullState(savedFullState)
        let bodyEnd = chunk.count
        Instruction.patchJump(at: jumpOver, in: &chunk)

        let captureCount = capturedNames.count

        // Push captured values in REVERSE order (CLOSURE pops them in LIFO)
        for captureName in capturedNames.reversed() {
            if let outerLocal = allOuterLocals.first(where: { $0.name == captureName }) {
                Instruction.loadLocal(outerLocal.slot, into: &chunk)
            } else {
                // Try global
                let nameIndex = chunk.constantPool.addString(captureName)
                Instruction.loadGlobal(nameIndex, into: &chunk)
            }
        }

        let params = closure.parameters.map { ParameterInfo(name: $0) }

        let funcRef = FunctionRef(
            name: closureName,
            parameters: params,
            localCount: UInt16(closure.parameters.count + 16),
            bytecode: [],
            bytecodeOffset: bodyStart
        )

        let funcIndex = chunk.constantPool.addFunction(funcRef)

        functionDebugInfo.append(FunctionDebugInfo(
            name: closureName,
            parameterNames: closure.parameters,
            sourceRange: (start: closure.location, end: closure.location),
            bytecodeRange: (start: bodyStart, end: bodyEnd)
        ))

        chunk.write(.closure)
        chunk.writeU16(funcIndex)
        chunk.write(UInt8(captureCount))

        // Restore outer state
        outerLocals = savedOuterLocals
        capturedNames = savedCapturedNames
    }

    private func compileAssignment(_ assign: AssignmentNode) {
        if let ident = assign.target as? IdentifierNode {
            // Check if this is an implicit self.property assignment inside a type method
            let isImplicitSelfProperty = compilingMethodOfType != nil
                && scopeTracker.resolve(ident.name) == nil
                && symbolTable.lookup(ident.name)?.isType != true
                && symbolTable.lookup(ident.name)?.kind == nil

            if isImplicitSelfProperty {
                // setProperty expects stack: [self, value] — pops val (top), then inst
                if let selfLocal = scopeTracker.resolve("self") {
                    Instruction.loadLocal(selfLocal.slot, into: &chunk)
                } else {
                    Instruction.loadLocal(0, into: &chunk)
                }
                compileExpression(assign.value)
                let nameIndex = chunk.constantPool.addPropertyName(ident.name)
                Instruction.setProperty(nameIndex, into: &chunk)
                chunk.write(.constNil) // assignment result for pop
            } else {
                compileExpression(assign.value)
                if let local = scopeTracker.resolve(ident.name) {
                    if !local.isMutable && local.isInitialized {
                        // Let was declared with an initializer — true reassignment is an error
                        diagnosticEngine.error("Cannot assign to immutable variable '\(ident.name)'", at: assign.location)
                    }
                    // Deferred let init (isInitialized=false) — allow assignment without error
                    chunk.write(.dup)
                    Instruction.storeLocal(local.slot, into: &chunk)
                } else {
                    // Global variable
                    // Check global immutability
                    if case .global(let isMutable) = symbolTable.lookup(ident.name)?.kind, !isMutable {
                        diagnosticEngine.error("Cannot assign to immutable variable '\(ident.name)'", at: assign.location)
                    }
                    chunk.write(.dup)
                    let nameIndex = chunk.constantPool.addString(ident.name)
                    Instruction.storeGlobal(nameIndex, into: &chunk)
                }
            }
        } else if let member = assign.target as? MemberAccessNode {
            // setProperty expects stack: [object, value] — pops val (top), then inst
            compileExpression(member.object)
            compileExpression(assign.value)
            let nameIndex = chunk.constantPool.addPropertyName(member.member)
            Instruction.setProperty(nameIndex, into: &chunk)
            chunk.write(.constNil) // assignment result for pop
        } else if let sub = assign.target as? SubscriptNode {
            // setIndex expects stack: [collection, index, value] — pops val, idx, col
            compileExpression(sub.object)
            compileExpression(sub.index)
            compileExpression(assign.value)
            chunk.write(.setIndex)
            // setIndex pushes the modified collection back — store it back to the variable
            if let objIdent = sub.object as? IdentifierNode {
                if let local = scopeTracker.resolve(objIdent.name) {
                    Instruction.storeLocal(local.slot, into: &chunk)
                } else {
                    let nameIndex = chunk.constantPool.addString(objIdent.name)
                    Instruction.storeGlobal(nameIndex, into: &chunk)
                }
            }
            chunk.write(.constNil) // assignment result for pop
        } else {
            diagnosticEngine.error("Invalid assignment target", at: assign.location)
        }
    }

    /// Parse a catch pattern string as an expression node.
    /// E.g., "ValidationError.tooSmall" → MemberAccessNode → loadGlobal("ValidationError.tooSmall")
    private func parsePatternAsExpression(_ pattern: String) -> ExpressionNode? {
        let parts = pattern.split(separator: ".")
        if parts.count == 2 {
            let typeName = String(parts[0])
            let caseName = String(parts[1])
            // Check if this is a known type
            if symbolTable.lookup(typeName)?.isType == true {
                return MemberAccessNode(
                    object: IdentifierNode(name: typeName, location: .unknown),
                    member: caseName,
                    location: .unknown
                )
            }
        }
        return nil
    }

    // MARK: - Source Map

    private func emitLocation(_ location: SourceLocation) {
        sourceMap.add(bytecodeOffset: chunk.count, location: location)
    }
}
