import LanternVM

// MARK: - Statement Compilation

extension BytecodeCompiler {
    func compileStatement(_ stmt: StatementNode) {
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
                if !suppressExpressionPop {
                    chunk.write(.pop)
                }
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

    func compileBlock(_ block: BlockNode) {
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

    func compileVariableDeclaration(_ decl: VariableDeclarationNode) {
        emitLocation(decl.location)

        // Tuple destructuring: let (a, b) = expr
        let varName = decl.name
        if varName.hasPrefix("(") && varName.hasSuffix(")"), let initExpr = decl.initializer {
            let inner = String(varName.dropFirst().dropLast())
            let parts = inner.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }

            // Compile the initializer once, store in temp
            compileExpression(initExpr)

            if scopeTracker.currentDepth == 0 {
                // Global scope: store temp, then extract each element
                let tempName = "__tuple_\(decl.location.line)"
                let tempIdx = chunk.constantPool.addString(tempName)
                chunk.write(.dup)
                Instruction.storeGlobal(tempIdx, into: &chunk)
                chunk.write(.pop) // pop the dup we kept on stack

                for (i, part) in parts.enumerated() {
                    if part == "_" { continue }
                    Instruction.loadGlobal(tempIdx, into: &chunk)
                    Instruction.constInt(i, into: &chunk)
                    chunk.write(.getIndex)
                    let nameIdx = chunk.constantPool.addString(part)
                    Instruction.storeGlobal(nameIdx, into: &chunk)
                    symbolTable.register(part, kind: .global(isMutable: decl.isMutable), location: decl.location)
                }
            } else {
                // Local scope: store temp, extract each element
                let tempSlot = scopeTracker.declare(name: "__tuple_\(decl.location.line)", isMutable: false)
                Instruction.storeLocal(tempSlot, into: &chunk)
                for (i, part) in parts.enumerated() {
                    if part == "_" { continue }
                    Instruction.loadLocal(tempSlot, into: &chunk)
                    Instruction.constInt(i, into: &chunk)
                    chunk.write(.getIndex)
                    let slot = scopeTracker.declare(name: part, isMutable: decl.isMutable)
                    Instruction.storeLocal(slot, into: &chunk)
                }
            }
            return
        }

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

    func compileIfStatement(_ stmt: IfStatementNode) {
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

    func compileGuardStatement(_ stmt: GuardStatementNode) {
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

    func compileWhileStatement(_ stmt: WhileStatementNode) {
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

    func compileForInStatement(_ stmt: ForInStatementNode) {
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

    func compileForInRange(_ stmt: ForInStatementNode, rangeExpr: BinaryExpressionNode) {
        let isInclusive = rangeExpr.op == .closedRange

        scopeTracker.pushScope()

        // Compile and store end value
        compileExpression(rangeExpr.right)
        let endSlot = scopeTracker.declare(name: "__end", isMutable: false)
        Instruction.storeLocal(endSlot, into: &chunk)

        // Compile and store start as loop variable
        compileExpression(rangeExpr.left)
        let loopVarName = stmt.variableName == "_" ? "__discard_\(chunk.count)" : stmt.variableName
        let varSlot = scopeTracker.declare(name: loopVarName, isMutable: true)
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

    func compileForInArray(_ stmt: ForInStatementNode) {
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

    func compileReturnStatement(_ stmt: ReturnStatementNode) {
        emitLocation(stmt.location)
        if let value = stmt.value {
            compileExpression(value)
            chunk.write(.return_)
        } else {
            chunk.write(.returnVoid)
        }
    }

    func compileBreakStatement(_ stmt: BreakStatementNode) {
        emitLocation(stmt.location)
        if loopDepth == 0 {
            diagnosticEngine.error("'break' outside of loop", at: stmt.location)
            return
        }
        let patchOffset = Instruction.jump(into: &chunk)
        breakTargets.append(patchOffset)
    }

    func compileContinueStatement(_ stmt: ContinueStatementNode) {
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

    func compileThrowStatement(_ stmt: ThrowStatementNode) {
        emitLocation(stmt.location)
        compileExpression(stmt.expression)
        chunk.write(.throw_)
    }

    func compileDoCatchStatement(_ stmt: DoCatchStatementNode) {
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
                // Specific catch pattern — compare by caseName for enum errors
                chunk.write(.dup) // dup error for comparison

                // Extract caseName from pattern (e.g., "LookupError.notFound(let key)" → "notFound")
                var patternCaseName: String?
                var patternBindings: [String] = []
                let patternParts = pattern.split(separator: ".")
                if patternParts.count == 2 {
                    var rawCase = String(patternParts[1])
                    if let paren = rawCase.firstIndex(of: "(") {
                        let bindStr = String(rawCase[rawCase.index(after: paren)..<rawCase.index(before: rawCase.endIndex)])
                        patternBindings = bindStr.split(separator: ",").map {
                            $0.trimmingCharacters(in: .whitespaces)
                             .replacingOccurrences(of: "let ", with: "")
                             .replacingOccurrences(of: "var ", with: "")
                        }
                        rawCase = String(rawCase[rawCase.startIndex..<paren])
                    }
                    patternCaseName = rawCase
                }

                if let caseName = patternCaseName {
                    // Compare by caseName
                    let caseNameIdx = chunk.constantPool.addPropertyName("caseName")
                    Instruction.getProperty(caseNameIdx, into: &chunk)
                    Instruction.constString(caseName, into: &chunk)
                } else if let patternExpr = parsePatternAsExpression(pattern) {
                    compileExpression(patternExpr)
                } else {
                    Instruction.constString(pattern, into: &chunk)
                }
                chunk.write(.eq)
                let skipCatch = Instruction.jumpIfFalse(into: &chunk)

                // Match: extract bindings, then execute catch body
                scopeTracker.pushScope()
                // Store error as global for reliable access
                let errorGlobalName = "__catch_error_\(chunk.count)"
                chunk.write(.dup)
                let errorNameIdx = chunk.constantPool.addString(errorGlobalName)
                Instruction.storeGlobal(errorNameIdx, into: &chunk)
                // Also declare as local for scope tracking
                let slot = scopeTracker.declare(name: "error", isMutable: false)
                _ = slot

                // Extract associated value bindings
                if !patternBindings.isEmpty {
                    // Get associatedValues array from the error
                    let assocIdx = chunk.constantPool.addPropertyName("associatedValues")
                    let errorNI = chunk.constantPool.addString(errorGlobalName)
                    Instruction.loadGlobal(errorNI, into: &chunk)
                    Instruction.getProperty(assocIdx, into: &chunk)
                    let arrGlobalName = "__catch_assoc_\(chunk.count)"
                    let arrNI = chunk.constantPool.addString(arrGlobalName)
                    Instruction.storeGlobal(arrNI, into: &chunk)
                    for (i, binding) in patternBindings.enumerated() {
                        Instruction.loadGlobal(arrNI, into: &chunk)
                        Instruction.constInt(i, into: &chunk)
                        chunk.write(.getIndex)
                        let bindNI = chunk.constantPool.addString(binding)
                        Instruction.storeGlobal(bindNI, into: &chunk)
                        symbolTable.register(binding, kind: .global(isMutable: false), location: .unknown)
                    }
                }

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

    func compileDeferStatement(_ stmt: DeferStatementNode) {
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

    func compileSwitchStatement(_ stmt: SwitchStatementNode) {
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
                    case .range(let startExpr, let endExpr, let isClosed):
                        // subject >= start && subject < end (or <= for closed)
                        // dup'd subject is on stack
                        chunk.write(.dup) // dup again so we have two copies for two comparisons
                        compileExpression(startExpr)
                        chunk.write(.gte) // subject >= start
                        // Now swap: we need subject for second comparison
                        // subject is under the bool result. We still have one dup on stack
                        let startCheck = Instruction.jumpIfFalse(into: &chunk)
                        // Pop the dup'd subject from .dup at top of loop, use the other
                        compileExpression(endExpr)
                        if isClosed {
                            chunk.write(.lte) // subject <= end
                        } else {
                            chunk.write(.lt) // subject < end
                        }
                        let jump2 = Instruction.jumpIfTrue(into: &chunk)
                        caseJumps.append(jump2)
                        // Jump here if start check failed — skip
                        let skipRange = Instruction.jump(into: &chunk)
                        Instruction.patchJump(at: startCheck, in: &chunk)
                        chunk.write(.pop) // pop the remaining dup'd subject
                        Instruction.patchJump(at: skipRange, in: &chunk)
                        continue
                    case .binding(_, _):
                        // Value binding always matches — the where clause is checked after
                        chunk.write(.pop) // pop the dup
                        Instruction.constBool(true, into: &chunk)
                        let jump = Instruction.jumpIfTrue(into: &chunk)
                        caseJumps.append(jump)
                        continue
                    case .tuple(let subPatterns):
                        // Element-wise comparison: subject[0] == pattern[0] && subject[1] == pattern[1] ...
                        var elemFailJumps: [Int] = []
                        for (i, subPat) in subPatterns.enumerated() {
                            if case .wildcard = subPat { continue }
                            chunk.write(.dup) // dup the dup'd subject
                            Instruction.constInt(i, into: &chunk)
                            chunk.write(.getIndex) // get element i
                            if case .expression(let expr) = subPat {
                                // Handle implicit member access for enum matching
                                if let member = expr as? MemberAccessNode, member.object is SelfNode {
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
                            } else if case .identifier(let name) = subPat {
                                Instruction.constString(name, into: &chunk)
                            }
                            chunk.write(.eq)
                            let fail = Instruction.jumpIfFalse(into: &chunk)
                            elemFailJumps.append(fail)
                        }
                        // All elements matched — pop dup'd subject and jump to body
                        chunk.write(.pop) // pop the dup'd subject
                        Instruction.constBool(true, into: &chunk)
                        let tupleJump = Instruction.jumpIfTrue(into: &chunk)
                        caseJumps.append(tupleJump)
                        // Patch failure jumps — they skip to after this pattern
                        for fj in elemFailJumps {
                            Instruction.patchJump(at: fj, in: &chunk)
                        }
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

                // Check for value binding pattern: `case let x where condition`
                let valueBinding = switchCase.patterns.compactMap { p -> (String, ExpressionNode?)? in
                    if case .binding(let name, let whereExpr) = p { return (name, whereExpr) }
                    return nil
                }.first

                // Extract enum bindings if this is an enumCase pattern
                let enumBindings = switchCase.patterns.compactMap { p -> (String, [String])? in
                    if case .enumCase(let cn, let binds) = p { return (cn, binds) }
                    return nil
                }.first

                if let (bindingName, whereExpr) = valueBinding {
                    if let whereExpr = whereExpr {
                        // case let x where condition:
                        // The subject is on the stack. We need x to be the subject.
                        // Approach: temporarily make x resolvable as a global pointing to the subject,
                        // or more simply: store subject in a temp global, bind x, eval where.
                        // Simplest: push a scope, store dup'd subject into binding, eval where.

                        // We need the binding variable accessible during where clause compilation.
                        // Use the stack: dup subject → store into a fresh local slot for x
                        scopeTracker.pushScope()
                        let slot = scopeTracker.declare(name: bindingName, isMutable: false)
                        chunk.write(.dup) // dup subject for binding
                        Instruction.storeLocal(slot, into: &chunk)

                        // Compile where clause — x resolves to the local we just created
                        compileExpression(whereExpr)
                        let whereCheck = Instruction.jumpIfFalse(into: &chunk)

                        // Save scope state before success path (so we can restore for failure path)
                        let savedState = scopeTracker.saveFullState()

                        // Where passed — pop subject, compile body, clean up scope
                        chunk.write(.pop)
                        compileBlock(switchCase.body)
                        let removed = scopeTracker.popScope()
                        for _ in removed { chunk.write(.pop) }
                        let endJump = Instruction.jump(into: &chunk)
                        endJumps.append(endJump)

                        // Where failed — restore scope state and pop it cleanly
                        Instruction.patchJump(at: whereCheck, in: &chunk)
                        scopeTracker.restoreFullState(savedState)
                        _ = scopeTracker.popScope()
                        // At runtime, the binding local is on the stack — pop it
                        // The subject remains on the stack for the next case
                        // But wait: storeLocal wrote the dup'd subject to a slot, not pushed it
                        // The dup pushed it, and storeLocal popped it from the stack to a slot
                        // So the stack is: [subject] (same as before the binding)
                        // No extra pop needed for the binding

                        Instruction.patchJump(at: nextCase, in: &chunk)
                        continue
                    } else {
                        chunk.write(.pop) // Pop the subject
                        compileBlock(switchCase.body)
                        let removed = scopeTracker.popScope()
                        for _ in removed { chunk.write(.pop) }
                    }
                } else if let (_, bindings) = enumBindings, !bindings.isEmpty {
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

                    // Don't pop subject — it's slot 0 (__switch_subject)
                    // The scope pop will clean up all locals including bindings
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

}
