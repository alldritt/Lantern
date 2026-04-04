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
