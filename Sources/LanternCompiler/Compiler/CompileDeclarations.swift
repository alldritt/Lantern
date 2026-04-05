import LanternVM

// MARK: - Declaration Compilation

extension BytecodeCompiler {
    func compileFunctionDeclaration(_ decl: FunctionDeclarationNode) {
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

        // Push captured values in REVERSE order (CLOSURE pops them in LIFO)
        // Use captureLocal for locals (ensures CaptureCell sharing) or loadGlobal for globals
        for captureName in capturedNames.reversed() {
            if let outerLocal = allOuterLocalsForFunc.first(where: { $0.name == captureName }) {
                chunk.write(.captureLocal)
                chunk.writeU16(UInt16(outerLocal.slot))
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

    func compileStructDeclaration(_ decl: StructDeclarationNode) {
        emitLocation(decl.location)
        let typeIndex = chunk.constantPool.addTypeName(decl.name)

        // Detect View conformance and @State/@Binding properties
        let savedIsViewType = isCompilingViewType
        let savedStateProps = statePropertyNames
        let savedBindingProps = bindingPropertyNames
        let savedObservedProps = observedObjectPropertyNames
        let savedEnvProps = environmentPropertyNames
        let savedAppStorage = appStorageProperties
        let savedTypeProps = currentTypePropertyNames
        let savedTypeMethods = currentTypeMethodNames
        isCompilingViewType = decl.conformances.contains("View")
        statePropertyNames = []
        bindingPropertyNames = []
        observedObjectPropertyNames = []
        environmentPropertyNames = []
        appStorageProperties = [:]
        currentTypePropertyNames = []

        var properties: [PropertyInfo] = []
        for member in decl.members {
            if let prop = member as? VariableDeclarationNode {
                properties.append(PropertyInfo(
                    name: prop.name,
                    typeAnnotation: prop.typeAnnotation,
                    isMutable: prop.isMutable
                ))
                if prop.attributes.contains("State") { statePropertyNames.insert(prop.name) }
                if prop.attributes.contains("Binding") { bindingPropertyNames.insert(prop.name) }
                if prop.attributes.contains("ObservedObject") || prop.attributes.contains("StateObject") {
                    observedObjectPropertyNames.insert(prop.name)
                }
                if prop.attributes.contains("Environment") { environmentPropertyNames.insert(prop.name) }
                if prop.attributes.contains("AppStorage"), let key = prop.attributeArgs["AppStorage"] {
                    appStorageProperties[prop.name] = key
                    statePropertyNames.insert(prop.name) // treat as @State for read/write
                }
            } else if let prop = member as? PropertyNode, !prop.isStatic {
                properties.append(PropertyInfo(
                    name: prop.name,
                    typeAnnotation: prop.typeAnnotation,
                    isMutable: prop.isMutable
                ))
                if prop.attributes.contains("State") { statePropertyNames.insert(prop.name) }
                if prop.attributes.contains("Binding") { bindingPropertyNames.insert(prop.name) }
                if prop.attributes.contains("ObservedObject") || prop.attributes.contains("StateObject") {
                    observedObjectPropertyNames.insert(prop.name)
                }
                if prop.attributes.contains("Environment") { environmentPropertyNames.insert(prop.name) }
                if prop.attributes.contains("Published") { publishedPropertyNames.insert(prop.name) }
            }
        }

        // Build the set of all known member names for this type
        currentTypePropertyNames = Set(properties.map(\.name))
        currentTypeMethodNames = []
        for member in decl.members {
            if let computed = member as? ComputedPropertyNode {
                currentTypePropertyNames.insert(computed.name)
            } else if let funcDecl = member as? FunctionDeclarationNode {
                currentTypeMethodNames.insert(funcDecl.name)
            }
        }

        // Compile methods and computed properties; track mutating methods for store-back
        for member in decl.members {
            if let funcDecl = member as? FunctionDeclarationNode {
                if funcDecl.isStatic {
                    compileStaticMethod(funcDecl, typeName: decl.name)
                } else {
                    compileTypeMethod(funcDecl, typeName: decl.name)
                    if funcDecl.isMutating {
                        userMutatingMethods[decl.name, default: []].insert(funcDecl.name)
                    }
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

        // Save @AppStorage mappings for this type before restoring
        if !appStorageProperties.isEmpty {
            allAppStorageMappings[decl.name] = appStorageProperties
        }

        // Restore View type tracking state
        currentTypePropertyNames = savedTypeProps
        currentTypeMethodNames = savedTypeMethods
        isCompilingViewType = savedIsViewType
        statePropertyNames = savedStateProps
        bindingPropertyNames = savedBindingProps
        observedObjectPropertyNames = savedObservedProps
        environmentPropertyNames = savedEnvProps
        appStorageProperties = savedAppStorage
    }

    func compileClassDeclaration(_ decl: ClassDeclarationNode) {
        emitLocation(decl.location)
        let typeIndex = chunk.constantPool.addTypeName(decl.name)

        // Track @Published properties for publishSet opcode emission
        let savedPublishedProps = publishedPropertyNames
        let savedTypeProps = currentTypePropertyNames
        let savedTypeMethods = currentTypeMethodNames
        publishedPropertyNames = []
        currentTypePropertyNames = []
        currentTypeMethodNames = []

        var properties: [PropertyInfo] = []
        for member in decl.members {
            if let prop = member as? VariableDeclarationNode {
                properties.append(PropertyInfo(
                    name: prop.name,
                    typeAnnotation: prop.typeAnnotation,
                    isMutable: prop.isMutable
                ))
                if prop.attributes.contains("Published") {
                    publishedPropertyNames.insert(prop.name)
                }
            } else if let prop = member as? PropertyNode {
                properties.append(PropertyInfo(
                    name: prop.name,
                    typeAnnotation: prop.typeAnnotation,
                    isMutable: prop.isMutable
                ))
                if prop.attributes.contains("Published") {
                    publishedPropertyNames.insert(prop.name)
                }
            }
        }

        // Build the set of all known member names for this type
        currentTypePropertyNames = Set(properties.map(\.name))
        currentTypeMethodNames = []
        for member in decl.members {
            if let computed = member as? ComputedPropertyNode {
                currentTypePropertyNames.insert(computed.name)
            } else if let funcDecl = member as? FunctionDeclarationNode {
                currentTypeMethodNames.insert(funcDecl.name)
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

        publishedPropertyNames = savedPublishedProps
        currentTypePropertyNames = savedTypeProps
        currentTypeMethodNames = savedTypeMethods
    }

    /// Compile a method as a global function "TypeName.methodName" with implicit self parameter
    func compileTypeMethod(_ decl: FunctionDeclarationNode, typeName: String) {
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
    func compileStaticMethod(_ decl: FunctionDeclarationNode, typeName: String) {
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
    func compileComputedProperty(_ prop: ComputedPropertyNode, typeName: String) {
        compileComputedPropertyDirect(prop, typeName: typeName)
    }

    func compileComputedPropertyDirect(_ prop: ComputedPropertyNode, typeName: String) {
        let getterName = "\(typeName).__get_\(prop.name)"

        let jumpOver = Instruction.jump(into: &chunk)
        let bodyStart = chunk.count

        let savedSlots = scopeTracker.saveSlotState()
        scopeTracker.restoreSlotState(0)
        let savedMethod = compilingMethodOfType
        compilingMethodOfType = typeName
        scopeTracker.pushScope()
        scopeTracker.declare(name: "self", isMutable: false)

        // Compile getter body with implicit return for the last expression.
        // In Swift, single-expression computed properties implicitly return.
        let stmts = prop.getter.statements
        for (i, stmt) in stmts.enumerated() {
            let isLast = (i == stmts.count - 1)
            if isLast, stmt is ExpressionStatementNode {
                // Last statement is an expression — compile it but don't pop,
                // then emit return_ so the value is returned from the getter.
                if let exprStmt = stmt as? ExpressionStatementNode {
                    compileExpression(exprStmt.expression)
                    chunk.write(.return_)
                } else {
                    compileStatement(stmt)
                }
            } else {
                compileStatement(stmt)
            }
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
    func compileCustomInit(_ initNode: InitializerNode, typeName: String, typeIndex: UInt16, propNames: [String], kind: TypeKind) {
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

    func emitMemberwiseInit(name: String, typeIndex: UInt16, propNames: [String], defaults: [ExpressionNode?] = [], kind: TypeKind) {
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

    func compileEnumDeclaration(_ decl: EnumDeclarationNode) {
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

    func compileExtension(_ ext: ExtensionNode) {
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
        // Record conformances from extension declarations
        if !ext.conformances.isEmpty {
            // Check if this type already has a TypeDebugInfo entry
            if let idx = typeDebugInfo.firstIndex(where: { $0.name == typeName }) {
                var info = typeDebugInfo[idx]
                info = TypeDebugInfo(
                    name: info.name,
                    kind: info.kind,
                    properties: info.properties,
                    methods: info.methods,
                    conformances: info.conformances + ext.conformances,
                    sourceRange: info.sourceRange
                )
                typeDebugInfo[idx] = info
            } else {
                // Create a new entry for built-in types extended with conformances
                typeDebugInfo.append(TypeDebugInfo(
                    name: typeName,
                    kind: .struct,
                    properties: [],
                    methods: [],
                    conformances: ext.conformances,
                    sourceRange: (start: ext.location, end: ext.location)
                ))
            }
        }
    }

    // MARK: - Expression Compilation

}
