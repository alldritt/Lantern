import Foundation
import LanternVM
import SwiftSyntax

/// Disambiguate SwiftSyntax.SourceLocation from LanternVM.SourceLocation.
typealias LanternSourceLocation = LanternVM.SourceLocation

/// Translates a SwiftSyntax tree into Lantern AST nodes.
final class SyntaxTranslator: SyntaxVisitor {
    let fileName: String
    let source: String
    private let sourceLines: [String]
    private(set) var diagnostics: [CompilerDiagnostic] = []
    private var converter: SourceLocationConverter?

    init(fileName: String, source: String) {
        self.fileName = fileName
        self.source = source
        self.sourceLines = source.components(separatedBy: "\n")
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Public Entry Point

    func translate(_ tree: SourceFileSyntax) -> SourceFileNode {
        self.converter = SourceLocationConverter(fileName: fileName, tree: tree)
        var statements: [StatementNode] = []
        for item in tree.statements {
            if let stmt = translateCodeBlockItem(item) {
                statements.append(stmt)
            }
        }
        return SourceFileNode(fileName: fileName, statements: statements, location: self.location(of: tree))
    }

    // MARK: - Location Helpers

    private func location(of node: some SyntaxProtocol) -> LanternSourceLocation {
        guard let conv = converter else { return .unknown }
        let loc = node.startLocation(converter: conv)
        return LanternSourceLocation(
            fileIndex: 0,
            line: UInt32(loc.line),
            column: UInt16(loc.column)
        )
    }

    private func emitDiagnostic(_ message: String, at node: some SyntaxProtocol, severity: DiagnosticSeverity = .warning) {
        let loc = self.location(of: node)
        diagnostics.append(CompilerDiagnostic(message: message, location: loc, severity: severity))
    }

    // MARK: - Code Block Items

    private func translateCodeBlockItem(_ item: CodeBlockItemSyntax) -> StatementNode? {
        translateItem(item.item)
    }

    private func translateItem(_ item: CodeBlockItemSyntax.Item) -> StatementNode? {
        switch item {
        case .decl(let decl):
            return translateDecl(decl)
        case .stmt(let stmt):
            return translateStmt(stmt)
        case .expr(let expr):
            let exprSyntax = ExprSyntax(expr)
            // if/switch at top level arrive as expressions in SwiftSyntax 600
            if let ifExpr = exprSyntax.as(IfExprSyntax.self) {
                return translateIfExpr(ifExpr)
            }
            if let switchExpr = exprSyntax.as(SwitchExprSyntax.self) {
                return translateSwitchExpr(switchExpr)
            }
            if let e = translateExpr(exprSyntax) {
                return ExpressionStatementNode(expression: e, location: self.location(of: expr))
            }
            return nil
        }
    }

    // MARK: - Declarations

    private func translateDecl(_ decl: DeclSyntax) -> StatementNode? {
        if let varDecl = decl.as(VariableDeclSyntax.self) {
            return translateVariableDecl(varDecl)
        } else if let funcDecl = decl.as(FunctionDeclSyntax.self) {
            return translateFunctionDecl(funcDecl)
        } else if let structDecl = decl.as(StructDeclSyntax.self) {
            return translateStructDecl(structDecl)
        } else if let classDecl = decl.as(ClassDeclSyntax.self) {
            return translateClassDecl(classDecl)
        } else if let enumDecl = decl.as(EnumDeclSyntax.self) {
            return translateEnumDecl(enumDecl)
        } else if let protocolDecl = decl.as(ProtocolDeclSyntax.self) {
            return translateProtocolDecl(protocolDecl)
        } else if let extensionDecl = decl.as(ExtensionDeclSyntax.self) {
            return translateExtensionDecl(extensionDecl)
        } else if let initDecl = decl.as(InitializerDeclSyntax.self) {
            return translateInitializerDecl(initDecl)
        } else {
            emitDiagnostic("Unsupported declaration: \(type(of: decl))", at: decl)
            return nil
        }
    }

    private func translateVariableDecl(_ decl: VariableDeclSyntax) -> StatementNode? {
        let isMutable = decl.bindingSpecifier.tokenKind == .keyword(.var)
        let isStatic = decl.modifiers.contains { $0.name.tokenKind == .keyword(.static) }

        guard let binding = decl.bindings.first else { return nil }
        let name = binding.pattern.trimmedDescription

        let typeAnnotation = binding.typeAnnotation?.type.trimmedDescription

        // Check for computed property (has accessor block with get/set)
        if let accessorBlock = binding.accessorBlock {
            let loc = self.location(of: decl)
            switch accessorBlock.accessors {
            case .getter(let body):
                let getterStatements = translateCodeBlockItemList(body)
                let getter = BlockNode(statements: getterStatements, location: loc)
                return ComputedPropertyNode(
                    name: name,
                    typeAnnotation: typeAnnotation,
                    isStatic: isStatic,
                    getter: getter,
                    location: loc
                )
            case .accessors(let accessorList):
                var getter: BlockNode?
                var setter: BlockNode?
                for accessor in accessorList {
                    let stmts: [StatementNode]
                    if let body = accessor.body {
                        stmts = translateCodeBlockItemList(body.statements)
                    } else {
                        stmts = []
                    }
                    let block = BlockNode(statements: stmts, location: self.location(of: accessor))
                    switch accessor.accessorSpecifier.tokenKind {
                    case .keyword(.get):
                        getter = block
                    case .keyword(.set):
                        setter = block
                    default:
                        break
                    }
                }
                if let getter {
                    return ComputedPropertyNode(
                        name: name,
                        typeAnnotation: typeAnnotation,
                        isStatic: isStatic,
                        getter: getter,
                        setter: setter,
                        location: loc
                    )
                }
                return nil
            }
        }

        let initializer = binding.initializer.flatMap { translateExpr($0.value) }

        if isStatic {
            return PropertyNode(
                name: name,
                isMutable: isMutable,
                isStatic: true,
                typeAnnotation: typeAnnotation,
                initializer: initializer,
                location: self.location(of: decl)
            )
        }

        return VariableDeclarationNode(
            name: name,
            isMutable: isMutable,
            typeAnnotation: typeAnnotation,
            initializer: initializer,
            location: self.location(of: decl)
        )
    }

    private func translateFunctionDecl(_ decl: FunctionDeclSyntax) -> FunctionDeclarationNode {
        let name = decl.name.trimmedDescription
        let params = translateParameterList(decl.signature.parameterClause.parameters)
        let returnType = decl.signature.returnClause?.type.trimmedDescription

        let isStatic = decl.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
        let isMutating = decl.modifiers.contains { $0.name.tokenKind == .keyword(.mutating) }
        let isAsync = decl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrowing = decl.signature.effectSpecifiers?.throwsClause != nil

        let bodyStatements: [StatementNode]
        if let body = decl.body {
            bodyStatements = translateCodeBlockItemList(body.statements)
        } else {
            bodyStatements = []
        }
        let body = BlockNode(statements: bodyStatements, location: self.location(of: decl))

        return FunctionDeclarationNode(
            name: name,
            parameters: params,
            returnType: returnType,
            body: body,
            isStatic: isStatic,
            isMutating: isMutating,
            isAsync: isAsync,
            isThrowing: isThrowing,
            location: self.location(of: decl)
        )
    }

    private func translateParameterList(_ params: FunctionParameterListSyntax) -> [FunctionDeclarationNode.Parameter] {
        params.map { param in
            let externalName: String?
            let firstName = param.firstName.trimmedDescription
            let secondName = param.secondName?.trimmedDescription

            if let secondName {
                externalName = firstName == "_" ? nil : firstName
                return FunctionDeclarationNode.Parameter(
                    externalName: externalName,
                    internalName: secondName,
                    typeAnnotation: param.type.trimmedDescription,
                    defaultValue: param.defaultValue.flatMap { translateExpr($0.value) }
                )
            } else {
                return FunctionDeclarationNode.Parameter(
                    externalName: nil,
                    internalName: firstName,
                    typeAnnotation: param.type.trimmedDescription,
                    defaultValue: param.defaultValue.flatMap { translateExpr($0.value) }
                )
            }
        }
    }

    private func translateStructDecl(_ decl: StructDeclSyntax) -> StructDeclarationNode {
        let name = decl.name.trimmedDescription
        let conformances = decl.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        let members = translateMemberBlock(decl.memberBlock)

        return StructDeclarationNode(
            name: name,
            conformances: conformances,
            members: members,
            location: self.location(of: decl)
        )
    }

    private func translateClassDecl(_ decl: ClassDeclSyntax) -> ClassDeclarationNode {
        let name = decl.name.trimmedDescription
        let inherited = decl.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []

        // First inherited type that starts with uppercase could be superclass
        let superclass = inherited.first
        let conformances = inherited.count > 1 ? Array(inherited.dropFirst()) : []

        let members = translateMemberBlock(decl.memberBlock)

        return ClassDeclarationNode(
            name: name,
            superclass: superclass,
            conformances: conformances,
            members: members,
            location: self.location(of: decl)
        )
    }

    private func translateEnumDecl(_ decl: EnumDeclSyntax) -> EnumDeclarationNode {
        let name = decl.name.trimmedDescription
        let conformances = decl.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []

        var cases: [EnumCaseNode] = []
        var members: [StatementNode] = []

        for member in decl.memberBlock.members {
            if let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) {
                for element in caseDecl.elements {
                    let caseName = element.name.trimmedDescription
                    let associatedValues = element.parameterClause?.parameters.map {
                        $0.type.trimmedDescription
                    }
                    let rawValue = element.rawValue.flatMap { translateExpr($0.value) }
                    cases.append(EnumCaseNode(
                        name: caseName,
                        associatedValues: associatedValues,
                        rawValue: rawValue,
                        location: self.location(of: element)
                    ))
                }
            } else if let stmt = translateDecl(member.decl) {
                members.append(stmt)
            }
        }

        return EnumDeclarationNode(
            name: name,
            conformances: conformances,
            cases: cases,
            members: members,
            location: self.location(of: decl)
        )
    }

    private func translateProtocolDecl(_ decl: ProtocolDeclSyntax) -> ProtocolDeclarationNode {
        let name = decl.name.trimmedDescription
        let inherits = decl.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []

        var requirements: [StatementNode] = []
        for member in decl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                guard let binding = varDecl.bindings.first else { continue }
                let propName = binding.pattern.trimmedDescription
                let typeAnnotation = binding.typeAnnotation?.type.trimmedDescription
                var isSettable = false
                if let accessorBlock = binding.accessorBlock {
                    if case .accessors(let accessors) = accessorBlock.accessors {
                        isSettable = accessors.contains { $0.accessorSpecifier.tokenKind == .keyword(.set) }
                    }
                }
                requirements.append(PropertyRequirementNode(
                    name: propName,
                    typeAnnotation: typeAnnotation,
                    isSettable: isSettable,
                    location: self.location(of: varDecl)
                ))
            } else if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                requirements.append(translateFunctionDecl(funcDecl))
            }
        }

        return ProtocolDeclarationNode(
            name: name,
            inherits: inherits,
            requirements: requirements,
            location: self.location(of: decl)
        )
    }

    private func translateExtensionDecl(_ decl: ExtensionDeclSyntax) -> ExtensionNode {
        let typeName = decl.extendedType.trimmedDescription
        let conformances = decl.inheritanceClause?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
        let members = translateMemberBlock(decl.memberBlock)

        return ExtensionNode(
            typeName: typeName,
            conformances: conformances,
            members: members,
            location: self.location(of: decl)
        )
    }

    private func translateInitializerDecl(_ decl: InitializerDeclSyntax) -> InitializerNode {
        let params = translateParameterList(decl.signature.parameterClause.parameters)
        let isFailable = decl.optionalMark != nil

        let bodyStatements: [StatementNode]
        if let body = decl.body {
            bodyStatements = translateCodeBlockItemList(body.statements)
        } else {
            bodyStatements = []
        }
        let body = BlockNode(statements: bodyStatements, location: self.location(of: decl))

        return InitializerNode(
            parameters: params,
            isFailable: isFailable,
            body: body,
            location: self.location(of: decl)
        )
    }

    private func translateMemberBlock(_ block: MemberBlockSyntax) -> [StatementNode] {
        block.members.compactMap { translateDecl($0.decl) }
    }

    // MARK: - Statements

    private func translateStmt(_ stmt: StmtSyntax) -> StatementNode? {
        if let returnStmt = stmt.as(ReturnStmtSyntax.self) {
            return translateReturnStmt(returnStmt)
        } else if let ifStmt = stmt.as(IfExprSyntax.self) {
            return translateIfExpr(ifStmt)
        } else if let guardStmt = stmt.as(GuardStmtSyntax.self) {
            return translateGuardStmt(guardStmt)
        } else if let whileStmt = stmt.as(WhileStmtSyntax.self) {
            return translateWhileStmt(whileStmt)
        } else if let forStmt = stmt.as(ForStmtSyntax.self) {
            return translateForStmt(forStmt)
        } else if let breakStmt = stmt.as(BreakStmtSyntax.self) {
            return BreakStatementNode(location: self.location(of: breakStmt))
        } else if let continueStmt = stmt.as(ContinueStmtSyntax.self) {
            return ContinueStatementNode(location: self.location(of: continueStmt))
        } else if let throwStmt = stmt.as(ThrowStmtSyntax.self) {
            return translateThrowStmt(throwStmt)
        } else if let doStmt = stmt.as(DoStmtSyntax.self) {
            return translateDoStmt(doStmt)
        } else if let deferStmt = stmt.as(DeferStmtSyntax.self) {
            return translateDeferStmt(deferStmt)
        } else if let switchExpr = stmt.as(SwitchExprSyntax.self) {
            return translateSwitchExpr(switchExpr)
        } else if let exprStmt = stmt.as(ExpressionStmtSyntax.self) {
            // if/switch wrapped in ExpressionStmtSyntax — handle as statements
            if let ifExpr = exprStmt.expression.as(IfExprSyntax.self) {
                return translateIfExpr(ifExpr)
            }
            if let switchExpr = exprStmt.expression.as(SwitchExprSyntax.self) {
                return translateSwitchExpr(switchExpr)
            }
            if let e = translateExpr(exprStmt.expression) {
                return ExpressionStatementNode(expression: e, location: self.location(of: exprStmt))
            }
            return nil
        } else {
            emitDiagnostic("Unsupported statement: \(type(of: stmt))", at: stmt)
            return nil
        }
    }

    private func translateReturnStmt(_ stmt: ReturnStmtSyntax) -> ReturnStatementNode {
        let value = stmt.expression.flatMap { translateExpr($0) }
        return ReturnStatementNode(value: value, location: self.location(of: stmt))
    }

    private func translateIfExpr(_ expr: IfExprSyntax) -> IfStatementNode {
        let loc = self.location(of: expr)

        var condition: ExpressionNode?
        var optionalBinding: OptionalBinding?

        if let first = expr.conditions.first {
            switch first.condition {
            case .expression(let condExpr):
                condition = translateExpr(condExpr)
            case .optionalBinding(let binding):
                let name = binding.pattern.trimmedDescription
                let isMutable = binding.bindingSpecifier.tokenKind == .keyword(.var)
                if let initializer = binding.initializer {
                    if let value = translateExpr(initializer.value) {
                        optionalBinding = OptionalBinding(name: name, isMutable: isMutable, value: value)
                    }
                }
            default:
                emitDiagnostic("Unsupported condition kind", at: first)
            }
        }

        let thenStatements = translateCodeBlockItemList(expr.body.statements)
        let thenBlock = BlockNode(statements: thenStatements, location: loc)

        var elseBlock: StatementNode?
        if let elseBody = expr.elseBody {
            switch elseBody {
            case .ifExpr(let elseIf):
                elseBlock = translateIfExpr(elseIf)
            case .codeBlock(let codeBlock):
                let stmts = translateCodeBlockItemList(codeBlock.statements)
                elseBlock = BlockNode(statements: stmts, location: self.location(of: codeBlock))
            }
        }

        return IfStatementNode(
            condition: condition,
            optionalBinding: optionalBinding,
            thenBlock: thenBlock,
            elseBlock: elseBlock,
            location: loc
        )
    }

    private func translateGuardStmt(_ stmt: GuardStmtSyntax) -> GuardStatementNode {
        let loc = self.location(of: stmt)

        var condition: ExpressionNode?
        var optionalBinding: OptionalBinding?

        if let first = stmt.conditions.first {
            switch first.condition {
            case .expression(let condExpr):
                condition = translateExpr(condExpr)
            case .optionalBinding(let binding):
                let name = binding.pattern.trimmedDescription
                let isMutable = binding.bindingSpecifier.tokenKind == .keyword(.var)
                if let initializer = binding.initializer {
                    if let value = translateExpr(initializer.value) {
                        optionalBinding = OptionalBinding(name: name, isMutable: isMutable, value: value)
                    }
                }
            default:
                emitDiagnostic("Unsupported guard condition kind", at: first)
            }
        }

        let elseStatements = translateCodeBlockItemList(stmt.body.statements)
        let elseBlock = BlockNode(statements: elseStatements, location: loc)

        return GuardStatementNode(
            condition: condition,
            optionalBinding: optionalBinding,
            elseBlock: elseBlock,
            location: loc
        )
    }

    private func translateWhileStmt(_ stmt: WhileStmtSyntax) -> WhileStatementNode {
        let loc = self.location(of: stmt)
        let condition: ExpressionNode
        if let first = stmt.conditions.first, case .expression(let condExpr) = first.condition {
            condition = translateExpr(condExpr) ?? BoolLiteralNode(value: true, location: loc)
        } else {
            condition = BoolLiteralNode(value: true, location: loc)
        }
        let bodyStatements = translateCodeBlockItemList(stmt.body.statements)
        let body = BlockNode(statements: bodyStatements, location: loc)
        return WhileStatementNode(condition: condition, body: body, location: loc)
    }

    private func translateForStmt(_ stmt: ForStmtSyntax) -> ForInStatementNode {
        let loc = self.location(of: stmt)
        let varName = stmt.pattern.trimmedDescription
        let iterable = translateExpr(stmt.sequence) ?? IdentifierNode(name: "_", location: loc)
        let bodyStatements = translateCodeBlockItemList(stmt.body.statements)
        let body = BlockNode(statements: bodyStatements, location: loc)
        return ForInStatementNode(variableName: varName, iterable: iterable, body: body, location: loc)
    }

    private func translateThrowStmt(_ stmt: ThrowStmtSyntax) -> ThrowStatementNode {
        let loc = self.location(of: stmt)
        let expr = translateExpr(stmt.expression) ?? StringLiteralNode(value: "error", location: loc)
        return ThrowStatementNode(expression: expr, location: loc)
    }

    private func translateDoStmt(_ stmt: DoStmtSyntax) -> DoCatchStatementNode {
        let loc = self.location(of: stmt)
        let bodyStatements = translateCodeBlockItemList(stmt.body.statements)
        let body = BlockNode(statements: bodyStatements, location: loc)

        let catchClauses: [CatchClause] = stmt.catchClauses.map { clause in
            let pattern = clause.catchItems.first?.pattern?.trimmedDescription
            let clauseStatements = translateCodeBlockItemList(clause.body.statements)
            let clauseBody = BlockNode(statements: clauseStatements, location: self.location(of: clause))
            return CatchClause(pattern: pattern, body: clauseBody)
        }

        return DoCatchStatementNode(body: body, catchClauses: catchClauses, location: loc)
    }

    private func translateDeferStmt(_ stmt: DeferStmtSyntax) -> DeferStatementNode {
        let loc = self.location(of: stmt)
        let bodyStatements = translateCodeBlockItemList(stmt.body.statements)
        let body = BlockNode(statements: bodyStatements, location: loc)
        return DeferStatementNode(body: body, location: loc)
    }

    private func translateSwitchExpr(_ expr: SwitchExprSyntax) -> SwitchStatementNode {
        let loc = self.location(of: expr)
        let subject = translateExpr(expr.subject) ?? IdentifierNode(name: "_", location: loc)

        let cases: [SwitchCase] = expr.cases.compactMap { switchCase in
            switch switchCase {
            case .switchCase(let c):
                let bodyStatements = translateCodeBlockItemList(c.statements)
                let body = BlockNode(statements: bodyStatements, location: self.location(of: c))

                switch c.label {
                case .case(let caseLabel):
                    let patterns: [CasePattern] = caseLabel.caseItems.map { item in
                        let patternText = item.pattern.trimmedDescription
                        if patternText == "_" {
                            return .wildcard
                        }
                        // Try to parse as expression
                        if let expr = translateExprFromText(patternText, at: item) {
                            return .expression(expr)
                        }
                        return .identifier(patternText)
                    }
                    return SwitchCase(patterns: patterns, body: body)
                case .default:
                    return SwitchCase(body: body, isDefault: true)
                }
            case .ifConfigDecl:
                return nil
            }
        }

        return SwitchStatementNode(subject: subject, cases: cases, location: loc)
    }

    private func translateExprFromText(_ text: String, at node: some SyntaxProtocol) -> ExpressionNode? {
        // Simple case: if it looks like a literal or identifier, create the corresponding node
        let loc = self.location(of: node)
        if let intVal = Int(text) {
            return IntLiteralNode(value: intVal, location: loc)
        }
        if let doubleVal = Double(text) {
            return DoubleLiteralNode(value: doubleVal, location: loc)
        }
        if text.hasPrefix("\"") && text.hasSuffix("\"") {
            let content = String(text.dropFirst().dropLast())
            return StringLiteralNode(value: content, location: loc)
        }
        if text == "true" { return BoolLiteralNode(value: true, location: loc) }
        if text == "false" { return BoolLiteralNode(value: false, location: loc) }
        if text == "nil" { return NilLiteralNode(location: loc) }

        // Member access like .case
        if text.hasPrefix(".") {
            let member = String(text.dropFirst())
            return MemberAccessNode(
                object: SelfNode(location: loc),
                member: member,
                location: loc
            )
        }
        return IdentifierNode(name: text, location: loc)
    }

    // MARK: - Expressions

    private func translateExpr(_ expr: ExprSyntax) -> ExpressionNode? {
        if let intLiteral = expr.as(IntegerLiteralExprSyntax.self) {
            let text = intLiteral.literal.trimmedDescription
            let value = Int(text) ?? 0
            return IntLiteralNode(value: value, location: self.location(of: intLiteral))
        } else if let floatLiteral = expr.as(FloatLiteralExprSyntax.self) {
            let text = floatLiteral.literal.trimmedDescription
            let value = Double(text) ?? 0.0
            return DoubleLiteralNode(value: value, location: self.location(of: floatLiteral))
        } else if let boolLiteral = expr.as(BooleanLiteralExprSyntax.self) {
            let value = boolLiteral.literal.tokenKind == .keyword(.true)
            return BoolLiteralNode(value: value, location: self.location(of: boolLiteral))
        } else if let stringLiteral = expr.as(StringLiteralExprSyntax.self) {
            return translateStringLiteral(stringLiteral)
        } else if let nilLiteral = expr.as(NilLiteralExprSyntax.self) {
            return NilLiteralNode(location: self.location(of: nilLiteral))
        } else if let identExpr = expr.as(DeclReferenceExprSyntax.self) {
            let name = identExpr.baseName.trimmedDescription
            if name == "self" {
                return SelfNode(location: self.location(of: identExpr))
            }
            return IdentifierNode(name: name, location: self.location(of: identExpr))
        } else if let memberExpr = expr.as(MemberAccessExprSyntax.self) {
            return translateMemberAccess(memberExpr)
        } else if let callExpr = expr.as(FunctionCallExprSyntax.self) {
            return translateFunctionCall(callExpr)
        } else if let subscriptExpr = expr.as(SubscriptCallExprSyntax.self) {
            return translateSubscriptExpr(subscriptExpr)
        } else if let infixExpr = expr.as(InfixOperatorExprSyntax.self) {
            return translateInfixOperator(infixExpr)
        } else if let prefixExpr = expr.as(PrefixOperatorExprSyntax.self) {
            return translatePrefixOperator(prefixExpr)
        } else if let postfixExpr = expr.as(PostfixOperatorExprSyntax.self) {
            return translatePostfixOperator(postfixExpr)
        } else if let arrayExpr = expr.as(ArrayExprSyntax.self) {
            return translateArrayLiteral(arrayExpr)
        } else if let dictExpr = expr.as(DictionaryExprSyntax.self) {
            return translateDictionaryLiteral(dictExpr)
        } else if let closureExpr = expr.as(ClosureExprSyntax.self) {
            return translateClosureExpr(closureExpr)
        } else if let tryExpr = expr.as(TryExprSyntax.self) {
            return translateTryExpr(tryExpr)
        } else if let awaitExpr = expr.as(AwaitExprSyntax.self) {
            return translateAwaitExpr(awaitExpr)
        } else if let assignExpr = expr.as(SequenceExprSyntax.self) {
            return translateSequenceExpr(assignExpr)
        } else if let ternary = expr.as(TernaryExprSyntax.self) {
            return translateTernaryExpr(ternary)
        } else if let forceUnwrap = expr.as(ForceUnwrapExprSyntax.self) {
            return translateForceUnwrap(forceUnwrap)
        } else if let optionalChain = expr.as(OptionalChainingExprSyntax.self) {
            return translateOptionalChaining(optionalChain)
        } else if let tupleExpr = expr.as(TupleExprSyntax.self) {
            // Treat single-element tuple as parenthesized expression
            if tupleExpr.elements.count == 1, let first = tupleExpr.elements.first {
                return translateExpr(first.expression)
            }
            emitDiagnostic("Tuple expressions are not supported", at: tupleExpr)
            return nil
        } else if let ifExpr = expr.as(IfExprSyntax.self) {
            // If-expression used as expression; translate as the statement form
            // and wrap, but for simplicity return nil and let the statement handle it
            emitDiagnostic("If-expression in expression context not fully supported", at: ifExpr)
            return nil
        } else if let switchExpr = expr.as(SwitchExprSyntax.self) {
            emitDiagnostic("Switch-expression in expression context not fully supported", at: switchExpr)
            return nil
        } else if let typeExpr = expr.as(TypeExprSyntax.self) {
            return TypeReferenceNode(typeName: typeExpr.type.trimmedDescription, location: self.location(of: typeExpr))
        } else {
            emitDiagnostic("Unsupported expression: \(type(of: expr))", at: expr)
            return nil
        }
    }

    private func translateStringLiteral(_ expr: StringLiteralExprSyntax) -> ExpressionNode {
        let loc = self.location(of: expr)
        var segments: [ExpressionNode] = []
        var hasInterpolation = false

        for segment in expr.segments {
            switch segment {
            case .stringSegment(let seg):
                let text = processEscapeSequences(seg.content.text)
                if !text.isEmpty {
                    segments.append(StringLiteralNode(value: text, location: self.location(of: seg)))
                }
            case .expressionSegment(let seg):
                hasInterpolation = true
                for expr in seg.expressions {
                    if let translated = translateExpr(expr.expression) {
                        segments.append(translated)
                    }
                }
            }
        }

        if hasInterpolation {
            return StringInterpolationNode(segments: segments, location: loc)
        }
        // Plain string
        let value = segments.compactMap { ($0 as? StringLiteralNode)?.value }.joined()
        return StringLiteralNode(value: value, location: loc)
    }

    private func processEscapeSequences(_ text: String) -> String {
        var result = ""
        var iter = text.makeIterator()
        while let ch = iter.next() {
            if ch == "\\" {
                if let next = iter.next() {
                    switch next {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    case "\\": result.append("\\")
                    case "\"": result.append("\"")
                    case "0": result.append("\0")
                    default:
                        result.append("\\")
                        result.append(next)
                    }
                } else {
                    result.append("\\")
                }
            } else {
                result.append(ch)
            }
        }
        return result
    }

    private func translateMemberAccess(_ expr: MemberAccessExprSyntax) -> ExpressionNode {
        let loc = self.location(of: expr)
        let member = expr.declName.baseName.trimmedDescription

        if let base = expr.base {
            if let obj = translateExpr(base) {
                return MemberAccessNode(object: obj, member: member, location: loc)
            }
        }
        // Implicit member access like `.red`
        return MemberAccessNode(
            object: SelfNode(location: loc),
            member: member,
            location: loc
        )
    }

    private func translateFunctionCall(_ expr: FunctionCallExprSyntax) -> ExpressionNode? {
        let loc = self.location(of: expr)
        guard let callee = translateExpr(expr.calledExpression) else { return nil }

        let arguments: [FunctionCallNode.Argument] = expr.arguments.compactMap { arg in
            guard let value = translateExpr(arg.expression) else { return nil }
            let label = arg.label?.trimmedDescription
            return FunctionCallNode.Argument(label: label, value: value)
        }

        // Check for trailing closure
        if let trailingClosure = expr.trailingClosure {
            let closureNode = translateClosureExpr(trailingClosure)
            var allArgs = arguments
            allArgs.append(FunctionCallNode.Argument(label: nil, value: closureNode))
            return FunctionCallNode(callee: callee, arguments: allArgs, location: loc)
        }

        return FunctionCallNode(callee: callee, arguments: arguments, location: loc)
    }

    private func translateSubscriptExpr(_ expr: SubscriptCallExprSyntax) -> ExpressionNode? {
        let loc = self.location(of: expr)
        guard let obj = translateExpr(expr.calledExpression) else { return nil }
        guard let firstArg = expr.arguments.first,
              let index = translateExpr(firstArg.expression) else { return nil }
        return SubscriptNode(object: obj, index: index, location: loc)
    }

    private func translateInfixOperator(_ expr: InfixOperatorExprSyntax) -> ExpressionNode? {
        let loc = self.location(of: expr)

        // Handle assignment
        if expr.operator.is(AssignmentExprSyntax.self) {
            guard let target = translateExpr(expr.leftOperand),
                  let value = translateExpr(expr.rightOperand) else { return nil }
            return AssignmentNode(target: target, value: value, location: loc)
        }

        guard let left = translateExpr(expr.leftOperand),
              let right = translateExpr(expr.rightOperand) else { return nil }

        let opText = expr.operator.trimmedDescription
        if let op = BinaryOperator(rawValue: opText) {
            return BinaryExpressionNode(op: op, left: left, right: right, location: loc)
        }

        // Compound assignment operators
        if opText == "+=" || opText == "-=" || opText == "*=" || opText == "/=" || opText == "%=" {
            let baseOp: BinaryOperator
            switch opText {
            case "+=": baseOp = .add
            case "-=": baseOp = .subtract
            case "*=": baseOp = .multiply
            case "/=": baseOp = .divide
            case "%=": baseOp = .modulo
            default: baseOp = .add
            }
            let binaryExpr = BinaryExpressionNode(op: baseOp, left: left, right: right, location: loc)
            return AssignmentNode(target: left, value: binaryExpr, location: loc)
        }

        emitDiagnostic("Unsupported binary operator: \(opText)", at: expr)
        return BinaryExpressionNode(op: .add, left: left, right: right, location: loc)
    }

    private func translatePrefixOperator(_ expr: PrefixOperatorExprSyntax) -> ExpressionNode? {
        let loc = self.location(of: expr)
        guard let operand = translateExpr(expr.expression) else { return nil }
        let opText = expr.operator.trimmedDescription
        if let op = UnaryOperator(rawValue: opText) {
            return UnaryExpressionNode(op: op, operand: operand, location: loc)
        }
        emitDiagnostic("Unsupported prefix operator: \(opText)", at: expr)
        return operand
    }

    private func translatePostfixOperator(_ expr: PostfixOperatorExprSyntax) -> ExpressionNode? {
        let loc = self.location(of: expr)
        guard let operand = translateExpr(expr.expression) else { return nil }
        let opText = expr.operator.trimmedDescription
        if opText == "!" {
            return ForceUnwrapNode(expression: operand, location: loc)
        }
        if opText == "?" {
            return OptionalChainingNode(expression: operand, location: loc)
        }
        emitDiagnostic("Unsupported postfix operator: \(opText)", at: expr)
        return operand
    }

    private func translateArrayLiteral(_ expr: ArrayExprSyntax) -> ArrayLiteralNode {
        let loc = self.location(of: expr)
        let elements = expr.elements.compactMap { translateExpr($0.expression) }
        return ArrayLiteralNode(elements: elements, location: loc)
    }

    private func translateDictionaryLiteral(_ expr: DictionaryExprSyntax) -> DictionaryLiteralNode {
        let loc = self.location(of: expr)
        switch expr.content {
        case .colon:
            return DictionaryLiteralNode(entries: [], location: loc)
        case .elements(let elements):
            let entries: [(key: ExpressionNode, value: ExpressionNode)] = elements.compactMap { element in
                guard let key = translateExpr(element.key),
                      let value = translateExpr(element.value) else { return nil }
                return (key: key, value: value)
            }
            return DictionaryLiteralNode(entries: entries, location: loc)
        }
    }

    private func translateClosureExpr(_ expr: ClosureExprSyntax) -> ClosureExpressionNode {
        let loc = self.location(of: expr)
        var params: [String] = []

        if let signature = expr.signature {
            if let paramList = signature.parameterClause {
                switch paramList {
                case .simpleInput(let simpleParams):
                    params = simpleParams.map { $0.name.trimmedDescription }
                case .parameterClause(let paramClause):
                    params = paramClause.parameters.map { $0.firstName.trimmedDescription }
                }
            }
        }

        let bodyStatements = translateCodeBlockItemList(expr.statements)
        let body = BlockNode(statements: bodyStatements, location: loc)

        // If no explicit params, detect $0, $1, etc. in the body
        if params.isEmpty {
            let bodyText = expr.statements.trimmedDescription
            var maxShorthand = -1
            for i in 0...9 {
                if bodyText.contains("$\(i)") { maxShorthand = i }
            }
            if maxShorthand >= 0 {
                for i in 0...maxShorthand {
                    params.append("$\(i)")
                }
            }
        }

        return ClosureExpressionNode(parameters: params, body: body, location: loc)
    }

    private func translateTryExpr(_ expr: TryExprSyntax) -> TryExpressionNode? {
        let loc = self.location(of: expr)
        guard let inner = translateExpr(expr.expression) else { return nil }
        let kind: TryKind
        if expr.questionOrExclamationMark?.tokenKind == .postfixQuestionMark {
            kind = .tryOptional
        } else if expr.questionOrExclamationMark?.tokenKind == .exclamationMark {
            kind = .tryForce
        } else {
            kind = .try
        }
        return TryExpressionNode(kind: kind, expression: inner, location: loc)
    }

    private func translateAwaitExpr(_ expr: AwaitExprSyntax) -> AwaitExpressionNode? {
        let loc = self.location(of: expr)
        guard let inner = translateExpr(expr.expression) else { return nil }
        return AwaitExpressionNode(expression: inner, location: loc)
    }

    private func translateSequenceExpr(_ expr: SequenceExprSyntax) -> ExpressionNode? {
        let elements = Array(expr.elements)
        if elements.count == 1 {
            return translateExpr(elements[0])
        }
        // For 3-element sequences: left op right
        if elements.count == 3 {
            guard let left = translateExpr(elements[0]),
                  let right = translateExpr(elements[2]) else { return nil }
            let opText = elements[1].trimmedDescription
            let loc = self.location(of: expr)
            // Assignment
            if opText == "=" {
                return AssignmentNode(target: left, value: right, location: loc)
            }
            // Compound assignment
            if opText == "+=" || opText == "-=" || opText == "*=" || opText == "/=" || opText == "%=" {
                let baseOp: BinaryOperator
                switch opText {
                case "+=": baseOp = .add; case "-=": baseOp = .subtract
                case "*=": baseOp = .multiply; case "/=": baseOp = .divide
                case "%=": baseOp = .modulo; default: baseOp = .add
                }
                let binaryExpr = BinaryExpressionNode(op: baseOp, left: left, right: right, location: loc)
                return AssignmentNode(target: left, value: binaryExpr, location: loc)
            }
            // Binary operator
            if let op = BinaryOperator(rawValue: opText) {
                return BinaryExpressionNode(op: op, left: left, right: right, location: loc)
            }
        }
        // For 5+ element sequences, use precedence-aware folding
        if elements.count >= 5 && elements.count % 2 == 1 {
            return foldSequenceWithPrecedence(elements, location: self.location(of: expr))
        }
        // Fallback
        if let first = elements.first { return translateExpr(first) }
        return nil
    }

    // MARK: - Precedence-Aware Sequence Folding

    private func operatorPrecedence(_ op: String) -> Int {
        switch op {
        case "=", "+=", "-=", "*=", "/=", "%=": return 0
        case "||": return 1
        case "&&": return 2
        case "==", "!=", "<", ">", "<=", ">=": return 3
        case "??": return 4
        case "..<", "...": return 5
        case "+", "-": return 6
        case "*", "/", "%": return 7
        case "<<", ">>": return 8
        default: return 6
        }
    }

    private func foldSequenceWithPrecedence(_ elements: [ExprSyntax], location: LanternSourceLocation) -> ExpressionNode? {
        // Convert to arrays of operands and operators
        var operands: [ExpressionNode] = []
        var operators: [(text: String, index: Int)] = []

        for (i, elem) in elements.enumerated() {
            if i % 2 == 0 {
                // Operand
                guard let expr = translateExpr(elem) else { return nil }
                operands.append(expr)
            } else {
                // Operator
                operators.append((text: elem.trimmedDescription, index: i))
            }
        }

        guard !operators.isEmpty else { return operands.first }

        // Check for assignment first (lowest precedence, right-associative)
        if let assignIdx = operators.firstIndex(where: { $0.text == "=" || $0.text == "+=" || $0.text == "-=" || $0.text == "*=" || $0.text == "/=" || $0.text == "%=" }) {
            let target = assignIdx == 0 ? operands[0] : foldBinaryRange(operands: operands, operators: operators, from: 0, to: assignIdx - 1)
            let value = assignIdx == operators.count - 1 ? operands[assignIdx + 1] : foldBinaryRange(operands: operands, operators: operators, from: assignIdx + 1, to: operators.count - 1)
            let opText = operators[assignIdx].text

            guard let target, let value else { return nil }

            if opText == "=" {
                return AssignmentNode(target: target, value: value, location: location)
            }
            // Compound assignment
            let baseOp: BinaryOperator
            switch opText {
            case "+=": baseOp = .add; case "-=": baseOp = .subtract
            case "*=": baseOp = .multiply; case "/=": baseOp = .divide
            case "%=": baseOp = .modulo; default: baseOp = .add
            }
            let binExpr = BinaryExpressionNode(op: baseOp, left: target, right: value, location: location)
            return AssignmentNode(target: target, value: binExpr, location: location)
        }

        // Fold by precedence (highest first)
        return foldBinaryRange(operands: operands, operators: operators, from: 0, to: operators.count - 1)
    }

    private func foldBinaryRange(operands: [ExpressionNode], operators: [(text: String, index: Int)], from: Int, to: Int) -> ExpressionNode? {
        if from > to { return operands[from] }
        if from == to {
            let opText = operators[from].text
            guard let op = BinaryOperator(rawValue: opText) else { return nil }
            return BinaryExpressionNode(op: op, left: operands[from], right: operands[from + 1], location: operands[from].location)
        }

        // Find the lowest-precedence operator (it becomes the root)
        var minPrec = Int.max
        var minIdx = from
        for i in from...to {
            let prec = operatorPrecedence(operators[i].text)
            if prec <= minPrec { // <= for left-associativity
                minPrec = prec
                minIdx = i
            }
        }

        let left: ExpressionNode?
        if minIdx == from {
            left = operands[from]
        } else {
            left = foldBinaryRange(operands: operands, operators: operators, from: from, to: minIdx - 1)
        }

        let right: ExpressionNode?
        if minIdx == to {
            right = operands[to + 1]
        } else {
            right = foldBinaryRange(operands: operands, operators: operators, from: minIdx + 1, to: to)
        }

        guard let left, let right else { return nil }
        let opText = operators[minIdx].text
        guard let op = BinaryOperator(rawValue: opText) else { return nil }
        return BinaryExpressionNode(op: op, left: left, right: right, location: left.location)
    }

    private func translateTernaryExpr(_ expr: TernaryExprSyntax) -> TernaryExpressionNode? {
        let loc = self.location(of: expr)
        guard let condition = translateExpr(expr.condition),
              let thenExpr = translateExpr(expr.thenExpression),
              let elseExpr = translateExpr(expr.elseExpression) else { return nil }
        return TernaryExpressionNode(condition: condition, thenExpr: thenExpr, elseExpr: elseExpr, location: loc)
    }

    private func translateForceUnwrap(_ expr: ForceUnwrapExprSyntax) -> ForceUnwrapNode? {
        let loc = self.location(of: expr)
        guard let inner = translateExpr(expr.expression) else { return nil }
        return ForceUnwrapNode(expression: inner, location: loc)
    }

    private func translateOptionalChaining(_ expr: OptionalChainingExprSyntax) -> OptionalChainingNode? {
        let loc = self.location(of: expr)
        guard let inner = translateExpr(expr.expression) else { return nil }
        return OptionalChainingNode(expression: inner, location: loc)
    }

    // MARK: - Helpers

    private func translateCodeBlockItemList(_ list: CodeBlockItemListSyntax) -> [StatementNode] {
        list.compactMap { translateCodeBlockItem($0) }
    }
}
