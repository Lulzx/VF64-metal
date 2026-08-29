import Foundation

enum VF64Opcode: UInt32, CaseIterable {
    case nop = 0, halt = 1, load = 2, store = 3, constant = 4, move = 5
    case select = 6, flagsClear = 7, flagsGet = 8, laneU64 = 9
    case add = 16, sub = 17, mul = 18, div = 19, sqrt = 20, fma = 21
    case remainder = 22, roundToInt = 23
    case eq = 32, le = 33, lt = 34, eqSignaling = 35, leQuiet = 36
    case ltQuiet = 37
    case ui32ToF64 = 48, ui64ToF64 = 49, i32ToF64 = 50, i64ToF64 = 51
    case f64ToUi32 = 52, f64ToUi64 = 53, f64ToI32 = 54, f64ToI64 = 55
    case f64ToF32 = 56, f64ToF16 = 57, f32ToF64 = 58, f16ToF64 = 59
}

enum VF64PrecisionMode: UInt32 {
    case ieee64 = 0, fast48 = 1, wide48 = 2
}

struct VF64Instruction {
    static let wordCount = 8
    var opcode: VF64Opcode
    var destination: UInt32 = 0
    var source0: UInt32 = 0
    var source1: UInt32 = 0
    var source2: UInt32 = 0
    var control: UInt32 = 0
    var immediate: UInt64 = 0

    var words: [UInt32] {
        [opcode.rawValue, destination, source0, source1, source2, control,
         UInt32(truncatingIfNeeded: immediate), UInt32(immediate >> 32)]
    }
}

struct VF64Program {
    static let magic: UInt32 = 0x56463634
    static let version: UInt32 = 0x00010000
    static let headerWords = 8
    static let maximumRegisters = 32

    var registerCount: Int
    var inputSlots: Int
    var outputSlots: Int
    var laneCount: Int
    var instructions: [VF64Instruction]

    var words: [UInt32] {
        [Self.magic, Self.version, UInt32(instructions.count),
         UInt32(registerCount), UInt32(inputSlots), UInt32(outputSlots),
         UInt32(laneCount), 0] + instructions.flatMap(\.words)
    }
}
