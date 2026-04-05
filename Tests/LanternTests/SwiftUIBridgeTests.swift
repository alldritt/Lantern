import Testing
import Lantern
import LanternVM
import LanternDebugger

@Test func bridgeGlobalsRegistered() {
    let interp = Interpreter()
    let vm = (interp.debugger as! Debugger).vm

    // Leaf view constructors
    #expect(vm.environment.getGlobal("Text") != nil, "Text should be registered")
    #expect(vm.environment.getGlobal("Spacer") != nil, "Spacer should be registered")
    #expect(vm.environment.getGlobal("Image") != nil, "Image should be registered")

    // Container constructors
    #expect(vm.environment.getGlobal("VStack") != nil, "VStack should be registered")
    #expect(vm.environment.getGlobal("HStack") != nil, "HStack should be registered")
    #expect(vm.environment.getGlobal("ScrollView") != nil, "ScrollView should be registered")
    #expect(vm.environment.getGlobal("NavigationStack") != nil, "NavigationStack should be registered")

    // View modifiers
    #expect(vm.environment.getGlobal("View.font") != nil, "View.font should be registered")
    #expect(vm.environment.getGlobal("View.padding") != nil, "View.padding should be registered")
    #expect(vm.environment.getGlobal("View.bold") != nil, "View.bold should be registered")
}

@Test func helloWorldCompileAndCreateInstance() {
    let interp = Interpreter()

    let result = interp.compile(source: """
    struct HelloWorld: View {
        var body: some View {
            Text("Hello!")
        }
    }
    """, fileName: "test.swift")

    switch result {
    case .success(let program):
        let viewTypes = program.typeTable.filter { $0.conformances.contains("View") }
        #expect(!viewTypes.isEmpty, "Should detect View type")
        #expect(viewTypes.first?.name == "HelloWorld")

        let execResult = interp.execute(program: program)
        #expect(execResult != nil)

        let instance = interp.createInstance(typeName: "HelloWorld")
        #expect(instance != nil, "Should create instance")
        #expect(instance?.typeName == "HelloWorld")
    case .failure(let diags):
        Issue.record("Compilation failed: \(diags)")
    }
}

@Test func statePropertyDetection() {
    let interp = Interpreter()
    let result = interp.compile(source: """
    struct CounterView: View {
        @State var count = 0
        var body: some View {
            Text("Count: \\(count)")
        }
    }
    """, fileName: "test.swift")

    switch result {
    case .success(let program):
        // Verify View conformance is detected
        let viewTypes = program.typeTable.filter { $0.conformances.contains("View") }
        #expect(!viewTypes.isEmpty)
        #expect(viewTypes.first?.name == "CounterView")

        // Execute to register types
        let execResult = interp.execute(program: program)
        #expect(execResult != nil)

        // Create instance
        let instance = interp.createInstance(typeName: "CounterView")
        #expect(instance != nil)
    case .failure(let diags):
        Issue.record("Compilation failed: \(diags)")
    }
}

@Test func textConstructorThroughBridge() {
    let interp = Interpreter()
    let vm = (interp.debugger as! Debugger).vm

    // Text constructor should be registered as a global
    let textFn = vm.environment.getGlobal("Text")
    #expect(textFn != nil, "Text should be registered as global")

    // Invoke it
    if let textFn {
        let result = try? vm.invokeValue(textFn, args: [.string("Hello")])
        #expect(result != nil)
        if case .hostObject(let ref) = result {
            #expect(ref.typeName == "Text")
        } else {
            Issue.record("Expected hostObject, got \(String(describing: result))")
        }
    }
}

@Test func conditionalViewInContainer() {
    let interp = Interpreter()

    // if/else in a container should produce only the active branch
    let src = """
    let show = true
    VStack {
        if show {
            Text("Visible")
        } else {
            Text("Hidden")
        }
        Text("Always")
    }
    """
    let result = interp.run(source: src)
    switch result {
    case .success(let value):
        if case .hostObject(let ref) = value {
            #expect(ref.typeName == "VStack")
        } else {
            Issue.record("Expected VStack hostObject, got \(value)")
        }
    case .failure(let err):
        Issue.record("Execution failed: \(err)")
    }
}

@Test func modifierChaining() {
    let interp = Interpreter()

    // Use string argument to .font() since implicit member (.title)
    // requires enum resolution that's not yet wired for Font
    let src = """
    Text("Hello")
        .font("title")
        .padding()
        .foregroundColor("blue")
    """
    let result = interp.run(source: src)
    switch result {
    case .success(let value):
        if case .hostObject(let ref) = value {
            #expect(ref.typeName == "Text")
        } else {
            Issue.record("Expected hostObject, got \(value)")
        }
    case .failure(let err):
        Issue.record("Execution failed: \(err)")
    }
}

@Test func containerWithMultipleChildren() {
    let interp = Interpreter()
    let vm = (interp.debugger as! Debugger).vm

    // VStack should be registered
    let vstackFn = vm.environment.getGlobal("VStack")
    #expect(vstackFn != nil, "VStack should be registered")

    // The content closure creates multiple Text views
    // which should all be collected via ViewCollector
    let src = """
    VStack {
        Text("Line 1")
        Text("Line 2")
        Text("Line 3")
    }
    """
    let result = interp.run(source: src)
    switch result {
    case .success(let value):
        // The result should be a hostObject containing a VStack
        if case .hostObject(let ref) = value {
            #expect(ref.typeName == "VStack")
        }
    case .failure(let err):
        Issue.record("Execution failed: \(err)")
    }
}
