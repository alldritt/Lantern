import LanternVM

// MARK: - Expression Compilation

extension BytecodeCompiler {
    func compileExpression(_ expr: ExpressionNode) {
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
        } else if let sub = expr as? SubscriptDefaultNode {
            // dict[key, default: value] — getIndex then nil-coalesce
            compileExpression(sub.object)
            compileExpression(sub.index)
            chunk.write(.getIndex)
            compileExpression(sub.defaultValue)
            chunk.write(.nilCoalesce)
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
    static let knownBuiltins: Set<String> = [
        "print", "debugPrint", "String", "Int", "Double", "Bool", "Array",
        "abs", "min", "max", "type", "zip", "+", "*"
    ]

    static let mutatingMethods: Set<String> = [
        "append", "remove", "removeLast", "removeAll", "removeValue",
        "insert", "sort", "reverse", "shuffle", "swapAt"
    ]

    func isMutatingMethod(_ name: String) -> Bool {
        Self.mutatingMethods.contains(name)
    }

    /// Check if a member access refers to a user-defined mutating method.
    /// Resolves the receiver's type from the symbol table and checks userMutatingMethods.
    func isUserMutatingMethod(_ memberAccess: MemberAccessNode) -> Bool {
        let methodName = memberAccess.member
        // Check all registered types for this method name
        for (_, methods) in userMutatingMethods {
            if methods.contains(methodName) { return true }
        }
        return false
    }

    func isKnownGlobal(_ name: String) -> Bool {
        Self.knownBuiltins.contains(name)
    }

    func compileIdentifier(_ ident: IdentifierNode) {
        // $binding syntax: $count → bindingCreate("count") for @State,
        // or load the BindingRef property for @Binding
        if ident.name.hasPrefix("$") && isCompilingViewType {
            let propName = String(ident.name.dropFirst())
            if statePropertyNames.contains(propName) {
                let nameIndex = chunk.constantPool.addString(propName)
                chunk.write(.bindingCreate)
                chunk.writeU16(nameIndex)
                return
            }
            if bindingPropertyNames.contains(propName) {
                // @Binding: load the BindingRef from the instance property
                if let selfLocal = scopeTracker.resolve("self") {
                    Instruction.loadLocal(selfLocal.slot, into: &chunk)
                } else {
                    Instruction.loadLocal(0, into: &chunk)
                }
                let nameIndex = chunk.constantPool.addPropertyName(propName)
                Instruction.getProperty(nameIndex, into: &chunk)
                return
            }
        }

        // Check locals first (inner to outer scope)
        if let local = scopeTracker.resolve(ident.name) {
            Instruction.loadLocal(local.slot, into: &chunk)
        } else if let captureIdx = capturedNames.firstIndex(of: ident.name) {
            // Already in capture list (e.g., from explicit [x] capture)
            chunk.write(.loadCapture)
            chunk.writeU16(UInt16(captureIdx))
        } else if !outerLocals.isEmpty, let _ = outerLocals.first(where: { $0.name == ident.name }) {
            // Captured variable from enclosing scope
            capturedNames.append(ident.name)
            chunk.write(.loadCapture)
            chunk.writeU16(UInt16(capturedNames.count - 1))
        } else if compilingMethodOfType != nil
                    && symbolTable.lookup(ident.name) == nil
                    && !isKnownGlobal(ident.name) {
            // Inside a type method body — unresolved identifiers are implicit self.property
            if isCompilingViewType && statePropertyNames.contains(ident.name) {
                // @State: read from state store
                let nameIndex = chunk.constantPool.addString(ident.name)
                chunk.write(.stateGet)
                chunk.writeU16(nameIndex)
            } else if isCompilingViewType && bindingPropertyNames.contains(ident.name) {
                // @Binding: load BindingRef from instance, read through it
                if let selfLocal = scopeTracker.resolve("self") {
                    Instruction.loadLocal(selfLocal.slot, into: &chunk)
                } else {
                    Instruction.loadLocal(0, into: &chunk)
                }
                let nameIndex = chunk.constantPool.addPropertyName(ident.name)
                Instruction.getProperty(nameIndex, into: &chunk)
                // The property value is a BindingRef — the VM's getProperty
                // will read through it transparently
            } else {
                if let selfLocal = scopeTracker.resolve("self") {
                    Instruction.loadLocal(selfLocal.slot, into: &chunk)
                } else {
                    Instruction.loadLocal(0, into: &chunk)
                }
                let nameIndex = chunk.constantPool.addPropertyName(ident.name)
                Instruction.getProperty(nameIndex, into: &chunk)
            }
        } else {
            // Global or unresolved — load from environment
            let nameIndex = chunk.constantPool.addString(ident.name)
            Instruction.loadGlobal(nameIndex, into: &chunk)
        }
    }

    func compileBinaryExpression(_ binary: BinaryExpressionNode) {
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

    func compileFunctionCall(_ call: FunctionCallNode) {
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
            } else if memberAccess.object is SelfNode,
                      case .enumCase(let typeName) = symbolTable.lookup(memberAccess.member)?.kind {
                // Implicit member call like `.loaded(42)` — enum constructor
                let qualifiedName = "\(typeName).\(memberAccess.member)"
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

    func compileClosureExpression(_ closure: ClosureExpressionNode) {
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

        // Pre-seed captures from explicit capture list [x, y, ...]
        // These variables are captured by VALUE at closure creation time
        for capName in closure.captureList {
            if !capturedNames.contains(capName) {
                capturedNames.append(capName)
            }
        }

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

        // Compile closure body. The last expression is implicitly returned
        // (matching Swift semantics for closures without explicit return).
        let stmts = closure.body.statements
        let hasExplicitReturn = stmts.contains { $0 is ReturnStatementNode }

        for (i, stmt) in stmts.enumerated() {
            let isLast = (i == stmts.count - 1)
            if isLast && !hasExplicitReturn && stmt is ExpressionStatementNode {
                // Last expression: compile without pop, then return the value
                compileExpression((stmt as! ExpressionStatementNode).expression)
                chunk.write(.return_)
            } else {
                compileStatement(stmt)
            }
        }

        // Emit return if the body doesn't already end with one
        if chunk.bytecode.last != Opcode.return_.rawValue && chunk.bytecode.last != Opcode.returnVoid.rawValue {
            chunk.write(.returnVoid)
        }

        _ = scopeTracker.popScope()
        scopeTracker.restoreFullState(savedFullState)
        let bodyEnd = chunk.count
        Instruction.patchJump(at: jumpOver, in: &chunk)

        let captureCount = capturedNames.count

        // Push captured values in REVERSE order (CLOSURE pops them in LIFO)
        // Use captureLocal for locals (ensures CaptureCell sharing) or loadGlobal for globals
        for captureName in capturedNames.reversed() {
            if let outerLocal = allOuterLocals.first(where: { $0.name == captureName }) {
                chunk.write(.captureLocal)
                chunk.writeU16(UInt16(outerLocal.slot))
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

    func compileAssignment(_ assign: AssignmentNode) {
        if let ident = assign.target as? IdentifierNode, ident.name == "_" {
            // Wildcard discard: _ = expr — just evaluate and discard
            compileExpression(assign.value)
            return
        }
        if let ident = assign.target as? IdentifierNode {
            // Check if this is an implicit self.property assignment inside a type method
            let isImplicitSelfProperty = compilingMethodOfType != nil
                && scopeTracker.resolve(ident.name) == nil
                && symbolTable.lookup(ident.name)?.isType != true
                && symbolTable.lookup(ident.name)?.kind == nil

            if isImplicitSelfProperty {
                // For @State properties in View types, use stateSet
                if isCompilingViewType && statePropertyNames.contains(ident.name) {
                    compileExpression(assign.value)
                    let nameIndex = chunk.constantPool.addString(ident.name)
                    chunk.write(.stateSet)
                    chunk.writeU16(nameIndex)
                    chunk.write(.constNil)
                } else {
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
                }
            } else {
                compileExpression(assign.value)
                if let local = scopeTracker.resolve(ident.name) {
                    if !local.isMutable && local.isInitialized {
                        diagnosticEngine.error("Cannot assign to immutable variable '\(ident.name)'", at: assign.location)
                    }
                    chunk.write(.dup)
                    Instruction.storeLocal(local.slot, into: &chunk)
                } else if let captureIdx = capturedNames.firstIndex(of: ident.name) {
                    // Assignment to a captured variable — emit STORE_CAPTURE
                    chunk.write(.dup)
                    chunk.write(.storeCapture)
                    chunk.writeU16(UInt16(captureIdx))
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
        } else if let sub = assign.target as? SubscriptDefaultNode {
            // dict[key, default: 0] += 1 — treat as subscript assignment
            compileExpression(sub.object)
            compileExpression(sub.index)
            compileExpression(assign.value)
            chunk.write(.setIndex)
            if let objIdent = sub.object as? IdentifierNode {
                if let local = scopeTracker.resolve(objIdent.name) {
                    Instruction.storeLocal(local.slot, into: &chunk)
                } else {
                    let nameIndex = chunk.constantPool.addString(objIdent.name)
                    Instruction.storeGlobal(nameIndex, into: &chunk)
                }
            }
            chunk.write(.constNil)
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
            } else if let memberAccess = sub.object as? MemberAccessNode,
                      let rootIdent = memberAccess.object as? IdentifierNode {
                // obj.prop[key] = value — store modified collection back to obj.prop
                // Stack: [modified_collection]
                // setProperty expects: [obj, value] → we need obj below modified_collection
                // Solution: store modified_collection as temp, load obj, load temp, setProperty
                scopeTracker.pushScope()
                let tempSlot = scopeTracker.declare(name: "__set_temp", isMutable: false)
                Instruction.storeLocal(tempSlot, into: &chunk)
                // Load the root object
                if let local = scopeTracker.resolve(rootIdent.name) {
                    Instruction.loadLocal(local.slot, into: &chunk)
                } else {
                    let nameIdx = chunk.constantPool.addString(rootIdent.name)
                    Instruction.loadGlobal(nameIdx, into: &chunk)
                }
                // Stack: [obj]
                Instruction.loadLocal(tempSlot, into: &chunk)
                // Stack: [obj, modified_collection]
                let propIdx = chunk.constantPool.addPropertyName(memberAccess.member)
                Instruction.setProperty(propIdx, into: &chunk)
                // setProperty modifies InstanceRef in-place (class-based)
                let removed = scopeTracker.popScope()
                for _ in removed { chunk.write(.pop) }
            }
            chunk.write(.constNil) // assignment result for pop
        } else {
            diagnosticEngine.error("Invalid assignment target", at: assign.location)
        }
    }

    /// Parse a catch pattern string as an expression node.
    /// E.g., "ValidationError.tooSmall" → MemberAccessNode → loadGlobal("ValidationError.tooSmall")
    func parsePatternAsExpression(_ pattern: String) -> ExpressionNode? {
        let parts = pattern.split(separator: ".")
        if parts.count == 2 {
            let typeName = String(parts[0])
            var caseName = String(parts[1])
            // Strip associated value bindings from case name: "notFound(let key)" → "notFound"
            if let parenIdx = caseName.firstIndex(of: "(") {
                caseName = String(caseName[caseName.startIndex..<parenIdx])
            }
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

}
