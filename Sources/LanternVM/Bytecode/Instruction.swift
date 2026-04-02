/// Convenience builders for common instruction sequences.
public enum Instruction {
    public static func constInt(_ value: Int, into chunk: inout Chunk) {
        chunk.write(.constInt); chunk.writeI64(value)
    }
    public static func constDouble(_ value: Double, into chunk: inout Chunk) {
        chunk.write(.constDouble); chunk.writeF64(value)
    }
    public static func constBool(_ value: Bool, into chunk: inout Chunk) {
        chunk.write(.constBool); chunk.write(value ? 1 : 0)
    }
    public static func constString(_ value: String, into chunk: inout Chunk) {
        let idx = chunk.constantPool.addString(value)
        chunk.write(.constString); chunk.writeU16(idx)
    }
    public static func loadLocal(_ slot: UInt16, into chunk: inout Chunk) {
        chunk.write(.loadLocal); chunk.writeU16(slot)
    }
    public static func storeLocal(_ slot: UInt16, into chunk: inout Chunk) {
        chunk.write(.storeLocal); chunk.writeU16(slot)
    }
    public static func loadGlobal(_ nameIndex: UInt16, into chunk: inout Chunk) {
        chunk.write(.loadGlobal); chunk.writeU16(nameIndex)
    }
    public static func storeGlobal(_ nameIndex: UInt16, into chunk: inout Chunk) {
        chunk.write(.storeGlobal); chunk.writeU16(nameIndex)
    }
    public static func jump(into chunk: inout Chunk) -> Int {
        chunk.write(.jump); let p = chunk.count; chunk.writeI16(0); return p
    }
    public static func jumpIfFalse(into chunk: inout Chunk) -> Int {
        chunk.write(.jumpIfFalse); let p = chunk.count; chunk.writeI16(0); return p
    }
    public static func jumpIfTrue(into chunk: inout Chunk) -> Int {
        chunk.write(.jumpIfTrue); let p = chunk.count; chunk.writeI16(0); return p
    }
    public static func patchJump(at patchOffset: Int, in chunk: inout Chunk) {
        let target = chunk.count
        chunk.patchI16(at: patchOffset, value: Int16(target - (patchOffset + 2)))
    }
    public static func call(argCount: UInt8, into chunk: inout Chunk) {
        chunk.write(.call); chunk.write(argCount)
    }
    public static func getProperty(_ nameIndex: UInt16, into chunk: inout Chunk) {
        chunk.write(.getProperty); chunk.writeU16(nameIndex)
    }
    public static func setProperty(_ nameIndex: UInt16, into chunk: inout Chunk) {
        chunk.write(.setProperty); chunk.writeU16(nameIndex)
    }
    public static func callMethod(_ nameIndex: UInt16, argCount: UInt8, into chunk: inout Chunk) {
        chunk.write(.callMethod); chunk.writeU16(nameIndex); chunk.write(argCount)
    }
    public static func callHost(_ fnIndex: UInt16, argCount: UInt8, into chunk: inout Chunk) {
        chunk.write(.callHost); chunk.writeU16(fnIndex); chunk.write(argCount)
    }
    public static func construct(_ typeIndex: UInt16, argCount: UInt8, into chunk: inout Chunk) {
        chunk.write(.construct); chunk.writeU16(typeIndex); chunk.write(argCount)
    }
}
