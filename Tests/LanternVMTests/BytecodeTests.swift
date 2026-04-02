import Testing
@testable import LanternVM

@Suite("Chunk")
struct ChunkTests {
    @Test func writeReadU16() {
        var c = Chunk(); c.writeU16(0x1234)
        #expect(c.readU16(at: 0) == 0x1234)
    }
    @Test func writeReadI64() {
        var c = Chunk(); c.writeI64(42); #expect(c.readI64(at: 0) == 42)
        var c2 = Chunk(); c2.writeI64(-1); #expect(c2.readI64(at: 0) == -1)
    }
    @Test func writeReadF64() {
        var c = Chunk(); c.writeF64(3.14); #expect(c.readF64(at: 0) == 3.14)
    }
    @Test func breakpointPatching() {
        var c = Chunk(); c.write(.add)
        let orig = c.patchBreakpoint(at: 0)
        #expect(orig == Opcode.add.rawValue)
        #expect(c.bytecode[0] == Opcode.breakpoint.rawValue)
        c.restoreOpcode(at: 0, original: orig)
        #expect(c.bytecode[0] == Opcode.add.rawValue)
    }
}

@Suite("Constant Pool")
struct ConstantPoolTests {
    @Test func stringDedup() {
        var p = ConstantPool()
        let i1 = p.addString("x"); let i2 = p.addString("x")
        #expect(i1 == i2); #expect(p.strings.count == 1)
    }
    @Test func stringLookup() {
        var p = ConstantPool(); let i = p.addString("hello")
        #expect(p.string(at: i) == "hello")
    }
    @Test func functionStorage() {
        var p = ConstantPool(); let f = FunctionRef(name: "foo")
        let i = p.addFunction(f); #expect(p.function(at: i)?.name == "foo")
    }
}

@Suite("Source Map")
struct SourceMapTests {
    @Test func lookup() {
        var m = SourceMap()
        let l1 = SourceLocation(line: 1, column: 1), l2 = SourceLocation(line: 2, column: 5)
        m.add(bytecodeOffset: 0, location: l1); m.add(bytecodeOffset: 10, location: l2)
        #expect(m.location(forOffset: 0) == l1)
        #expect(m.location(forOffset: 10) == l2)
        #expect(m.location(forOffset: 5) == l1) // between entries
    }
    @Test func reverseLookup() {
        var m = SourceMap()
        m.add(bytecodeOffset: 0, location: SourceLocation(line: 1, column: 1))
        m.add(bytecodeOffset: 5, location: SourceLocation(line: 1, column: 10))
        m.add(bytecodeOffset: 10, location: SourceLocation(line: 2, column: 1))
        #expect(m.offsets(forLine: 1).count == 2)
    }
    @Test func firstExecutableOffset() {
        var m = SourceMap()
        m.add(bytecodeOffset: 0, location: SourceLocation(line: 3, column: 1))
        m.add(bytecodeOffset: 10, location: SourceLocation(line: 5, column: 1))
        let result = m.firstExecutableOffset(atOrAfterLine: 4)
        #expect(result?.line == 5); #expect(result?.offset == 10)
    }
}

@Suite("VM Arithmetic")
struct VMArithmeticTests {
    private func run(_ build: (inout Chunk) -> Void) -> Value? {
        var chunk = Chunk(); build(&chunk); chunk.write(.halt)
        let prog = CompiledProgram(bytecode: chunk.bytecode, constantPool: chunk.constantPool)
        let vm = VM(); vm.load(prog); vm.run()
        return vm.stackSnapshot.last
    }

    @Test func addInts() { #expect(run { c in Instruction.constInt(2, into: &c); Instruction.constInt(3, into: &c); c.write(.add) } == .int(5)) }
    @Test func addDoubles() { #expect(run { c in Instruction.constDouble(1.5, into: &c); Instruction.constDouble(2.5, into: &c); c.write(.add) } == .double(4.0)) }
    @Test func subtract() { #expect(run { c in Instruction.constInt(10, into: &c); Instruction.constInt(3, into: &c); c.write(.sub) } == .int(7)) }
    @Test func multiply() { #expect(run { c in Instruction.constInt(4, into: &c); Instruction.constInt(5, into: &c); c.write(.mul) } == .int(20)) }
    @Test func divide() { #expect(run { c in Instruction.constInt(10, into: &c); Instruction.constInt(3, into: &c); c.write(.div) } == .int(3)) }
    @Test func modulo() { #expect(run { c in Instruction.constInt(10, into: &c); Instruction.constInt(3, into: &c); c.write(.mod) } == .int(1)) }
    @Test func negate() { #expect(run { c in Instruction.constInt(5, into: &c); c.write(.neg) } == .int(-5)) }
    @Test func stringConcat() { #expect(run { c in Instruction.constString("a", into: &c); Instruction.constString("b", into: &c); c.write(.add) } == .string("ab")) }

    @Test func constBool() {
        #expect(run { c in Instruction.constBool(true, into: &c) } == .bool(true))
        #expect(run { c in Instruction.constBool(false, into: &c) } == .bool(false))
    }

    @Test func comparison() {
        #expect(run { c in Instruction.constInt(5, into: &c); Instruction.constInt(5, into: &c); c.write(.eq) } == .bool(true))
        #expect(run { c in Instruction.constInt(3, into: &c); Instruction.constInt(5, into: &c); c.write(.lt) } == .bool(true))
        #expect(run { c in Instruction.constInt(5, into: &c); Instruction.constInt(3, into: &c); c.write(.gt) } == .bool(true))
    }

    @Test func logic() {
        #expect(run { c in Instruction.constBool(true, into: &c); c.write(.not) } == .bool(false))
    }
}

@Suite("ValueStack")
struct ValueStackTests {
    @Test func pushPop() {
        var s = ValueStack(); try! s.push(.int(42))
        #expect(s.pop() == .int(42)); #expect(s.isEmpty)
    }
    @Test func peek() {
        var s = ValueStack(); try! s.push(.int(1)); try! s.push(.int(2))
        #expect(s.peek() == .int(2)); #expect(s.peek(1) == .int(1))
    }
    @Test func subscriptAccess() {
        var s = ValueStack(); try! s.push(.int(10)); try! s.push(.int(20))
        #expect(s[0] == .int(10)); s[0] = .int(99); #expect(s[0] == .int(99))
    }
}
