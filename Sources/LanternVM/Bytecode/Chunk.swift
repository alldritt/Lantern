/// A mutable bytecode buffer with read/write helpers.
public struct Chunk: Sendable {
    public var bytecode: [UInt8] = []
    public var constantPool: ConstantPool = ConstantPool()

    public init() {}

    // MARK: - Writing

    public mutating func write(_ byte: UInt8) { bytecode.append(byte) }
    public mutating func write(_ opcode: Opcode) { bytecode.append(opcode.rawValue) }

    public mutating func writeU16(_ value: UInt16) {
        bytecode.append(UInt8(value >> 8))
        bytecode.append(UInt8(value & 0xFF))
    }

    public mutating func writeI16(_ value: Int16) {
        writeU16(UInt16(bitPattern: value))
    }

    public mutating func writeI64(_ value: Int) {
        let bits = UInt64(bitPattern: Int64(value))
        for shift in stride(from: 56, through: 0, by: -8) {
            bytecode.append(UInt8((bits >> shift) & 0xFF))
        }
    }

    public mutating func writeF64(_ value: Double) {
        let bits = value.bitPattern
        for shift in stride(from: 56, through: 0, by: -8) {
            bytecode.append(UInt8((bits >> shift) & 0xFF))
        }
    }

    // MARK: - Reading

    public func readU8(at offset: Int) -> UInt8? {
        guard offset < bytecode.count else { return nil }
        return bytecode[offset]
    }

    public func readU16(at offset: Int) -> UInt16? {
        guard offset + 1 < bytecode.count else { return nil }
        return UInt16(bytecode[offset]) << 8 | UInt16(bytecode[offset + 1])
    }

    public func readI16(at offset: Int) -> Int16? {
        guard let u = readU16(at: offset) else { return nil }
        return Int16(bitPattern: u)
    }

    public func readI64(at offset: Int) -> Int? {
        guard offset + 7 < bytecode.count else { return nil }
        var bits: UInt64 = 0
        for i in 0..<8 { bits = (bits << 8) | UInt64(bytecode[offset + i]) }
        return Int(Int64(bitPattern: bits))
    }

    public func readF64(at offset: Int) -> Double? {
        guard offset + 7 < bytecode.count else { return nil }
        var bits: UInt64 = 0
        for i in 0..<8 { bits = (bits << 8) | UInt64(bytecode[offset + i]) }
        return Double(bitPattern: bits)
    }

    // MARK: - Patching

    public var count: Int { bytecode.count }

    public mutating func patchU16(at offset: Int, value: UInt16) {
        bytecode[offset] = UInt8(value >> 8)
        bytecode[offset + 1] = UInt8(value & 0xFF)
    }

    public mutating func patchI16(at offset: Int, value: Int16) {
        patchU16(at: offset, value: UInt16(bitPattern: value))
    }

    public mutating func patchBreakpoint(at offset: Int) -> UInt8 {
        let original = bytecode[offset]
        bytecode[offset] = Opcode.breakpoint.rawValue
        return original
    }

    public mutating func restoreOpcode(at offset: Int, original: UInt8) {
        bytecode[offset] = original
    }
}
