/// The complete opcode set for the Lantern bytecode VM.
public enum Opcode: UInt8, Sendable, CaseIterable {
    // MARK: Constants
    case constInt       = 0x00  // i64
    case constDouble    = 0x01  // f64
    case constBool      = 0x02  // u8 (0 or 1)
    case constString    = 0x03  // u16 (constant pool index)
    case constNil       = 0x04

    // MARK: Arithmetic
    case add            = 0x10
    case sub            = 0x11
    case mul            = 0x12
    case div            = 0x13
    case mod            = 0x14
    case neg            = 0x15

    // MARK: Comparison
    case eq             = 0x20
    case neq            = 0x21
    case lt             = 0x22
    case gt             = 0x23
    case lte            = 0x24
    case gte            = 0x25

    // MARK: Logic
    case not            = 0x28
    case and            = 0x29
    case or             = 0x2A

    // MARK: Stack
    case pop            = 0x30
    case dup            = 0x31

    // MARK: Variables
    case loadLocal      = 0x38  // u16 slot
    case storeLocal     = 0x39  // u16 slot
    case loadCapture    = 0x3A  // u16 index
    case storeCapture   = 0x3B  // u16 index
    case loadGlobal     = 0x3C  // u16 name index
    case storeGlobal    = 0x3D  // u16 name index
    case captureLocal   = 0x3E  // u16 slot — ensure cell, push .cell for CLOSURE

    // MARK: Control Flow
    case jump           = 0x40  // i16 offset
    case jumpIfTrue     = 0x41  // i16 offset
    case jumpIfFalse    = 0x42  // i16 offset
    case loop           = 0x43  // i16 offset (backward)

    // MARK: Functions
    case call           = 0x48  // u8 arg count
    case return_        = 0x49
    case returnVoid     = 0x4A
    case closure        = 0x4B  // u16 fn_index, u8 capture_count

    // MARK: Properties & Methods
    case getProperty    = 0x50  // u16 name index
    case setProperty    = 0x51  // u16 name index
    case getIndex       = 0x52
    case setIndex       = 0x53
    case callMethod     = 0x54  // u16 name index, u8 arg count

    // MARK: Host Bridge
    case callHost       = 0x58  // u16 fn_index, u8 arg count
    case construct      = 0x59  // u16 type_index, u8 arg count

    // MARK: Optionals
    case wrapOptional   = 0x60
    case unwrapOptional = 0x61
    case optionalChain  = 0x62  // i16 jump offset if nil
    case nilCoalesce    = 0x63

    // MARK: Collections
    case makeArray      = 0x68  // u16 element count
    case makeDict       = 0x69  // u16 entry count

    // MARK: String Interpolation
    case interpolate    = 0x70  // u8 segment count

    // MARK: Range
    case makeRange      = 0x71  // u8 inclusive flag

    // MARK: Error Handling
    case throw_         = 0x78
    case deferPush      = 0x79  // u16 bytecode offset
    case deferPop       = 0x7A
    case pushHandler    = 0x7B  // i16 offset to catch block
    case popHandler     = 0x7C

    // MARK: SwiftUI State
    case stateInit      = 0x80  // u16 name index
    case stateGet       = 0x81  // u16 name index
    case stateSet       = 0x82  // u16 name index
    case bindingCreate  = 0x83  // u16 name index
    case publishSet     = 0x84  // u16 name index

    // MARK: View Builder
    case viewCollect    = 0x88
    case viewGroup      = 0x89  // u8 count

    // MARK: Debug
    case breakpoint     = 0xFE
    case halt           = 0xFF
}

extension Opcode {
    /// Total size of this instruction in bytes (opcode + operands).
    public var instructionSize: Int {
        switch self {
        // 1 byte (opcode only)
        case .constNil,
             .add, .sub, .mul, .div, .mod, .neg,
             .eq, .neq, .lt, .gt, .lte, .gte,
             .not, .and, .or,
             .pop, .dup,
             .return_, .returnVoid,
             .getIndex, .setIndex,
             .wrapOptional, .unwrapOptional, .nilCoalesce,
             .throw_, .deferPop, .popHandler,
             .viewCollect,
             .breakpoint, .halt:
            return 1

        // 2 bytes (opcode + u8)
        case .constBool, .call, .interpolate, .makeRange, .viewGroup:
            return 2

        // 3 bytes (opcode + u16 or i16)
        case .constString,
             .loadLocal, .storeLocal, .loadCapture, .storeCapture,
             .loadGlobal, .storeGlobal, .captureLocal,
             .jump, .jumpIfTrue, .jumpIfFalse, .loop,
             .getProperty, .setProperty,
             .optionalChain,
             .makeArray, .makeDict,
             .deferPush, .pushHandler,
             .stateInit, .stateGet, .stateSet, .bindingCreate, .publishSet:
            return 3

        // 4 bytes (opcode + u16 + u8)
        case .closure, .callMethod, .callHost, .construct:
            return 4

        // 9 bytes (opcode + i64 or f64)
        case .constInt, .constDouble:
            return 9
        }
    }
}
