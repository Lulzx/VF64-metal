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

enum VF64ValidationError: Error, CustomStringConvertible {
    case invalid(String)

    var description: String {
        switch self { case .invalid(let message): return message }
    }
}

extension VF64Instruction {
    static func control(
        rounding: UInt32 = 0, exact: Bool = false,
        mode: VF64PrecisionMode = .ieee64
    ) -> UInt32 {
        rounding | (exact ? 8 : 0) | (mode.rawValue << 8)
    }
}

extension VF64Program {
    static func decode(_ words: [UInt32]) throws -> VF64Program {
        guard words.count >= headerWords else {
            throw VF64ValidationError.invalid("truncated VF64 header")
        }
        guard words[0] == magic else {
            throw VF64ValidationError.invalid("invalid VF64 magic")
        }
        guard words[1] == version else {
            throw VF64ValidationError.invalid("unsupported VF64 version")
        }
        guard words[7] == 0 else {
            throw VF64ValidationError.invalid("unsupported VF64 feature bits")
        }
        let count = Int(words[2])
        guard words.count == headerWords + count * VF64Instruction.wordCount else {
            throw VF64ValidationError.invalid("invalid VF64 program length")
        }
        var instructions: [VF64Instruction] = []
        instructions.reserveCapacity(count)
        for index in 0..<count {
            let base = headerWords + index * VF64Instruction.wordCount
            guard let opcode = VF64Opcode(rawValue: words[base]) else {
                throw VF64ValidationError.invalid(
                    "unknown VF64 opcode \(words[base]) at instruction \(index)"
                )
            }
            instructions.append(VF64Instruction(
                opcode: opcode,
                destination: words[base + 1],
                source0: words[base + 2], source1: words[base + 3],
                source2: words[base + 4], control: words[base + 5],
                immediate: UInt64(words[base + 6]) |
                    (UInt64(words[base + 7]) << 32)
            ))
        }
        let program = VF64Program(
            registerCount: Int(words[3]), inputSlots: Int(words[4]),
            outputSlots: Int(words[5]), laneCount: Int(words[6]),
            instructions: instructions
        )
        try program.validate()
        return program
    }

    func validate() throws {
        guard (1...Self.maximumRegisters).contains(registerCount) else {
            throw VF64ValidationError.invalid("VF64 register count must be 1...32")
        }
        guard laneCount > 0 else {
            throw VF64ValidationError.invalid("VF64 lane count must be positive")
        }
        guard instructions.count <= 4096 else {
            throw VF64ValidationError.invalid("VF64 instruction limit exceeded")
        }
        var initialized = Set<UInt32>()

        func register(_ value: UInt32, at index: Int) throws {
            guard value < UInt32(registerCount) else {
                throw VF64ValidationError.invalid(
                    "register \(value) out of range at instruction \(index)"
                )
            }
        }
        func source(_ value: UInt32, at index: Int) throws {
            try register(value, at: index)
            guard initialized.contains(value) else {
                throw VF64ValidationError.invalid(
                    "read of uninitialized register \(value) at instruction \(index)"
                )
            }
        }
        func control(_ value: UInt32, at index: Int) throws -> (UInt32, UInt32, Bool) {
            guard value & 0xfffffcf0 == 0 else {
                throw VF64ValidationError.invalid(
                    "reserved control bits at instruction \(index)"
                )
            }
            let rounding = value & 7
            let mode = (value >> 8) & 3
            guard rounding <= 4 && mode <= 2 else {
                throw VF64ValidationError.invalid(
                    "invalid control value at instruction \(index)"
                )
            }
            return (rounding, mode, value & 8 != 0)
        }

        for (index, instruction) in instructions.enumerated() {
            let op = instruction.opcode
            let noFields = instruction.destination == 0 &&
                instruction.source0 == 0 && instruction.source1 == 0 &&
                instruction.source2 == 0 && instruction.control == 0 &&
                instruction.immediate == 0
            switch op {
            case .nop, .halt, .flagsClear:
                guard noFields else {
                    throw VF64ValidationError.invalid(
                        "unexpected operands at instruction \(index)"
                    )
                }
            case .load:
                try register(instruction.destination, at: index)
                guard instruction.immediate < UInt64(inputSlots),
                      instruction.source0 == 0, instruction.source1 == 0,
                      instruction.source2 == 0, instruction.control == 0 else {
                    throw VF64ValidationError.invalid("invalid load at instruction \(index)")
                }
                initialized.insert(instruction.destination)
            case .store:
                try source(instruction.source0, at: index)
                guard instruction.immediate < UInt64(outputSlots),
                      instruction.destination == 0, instruction.source1 == 0,
                      instruction.source2 == 0, instruction.control == 0 else {
                    throw VF64ValidationError.invalid("invalid store at instruction \(index)")
                }
            case .constant:
                try register(instruction.destination, at: index)
                guard instruction.source0 == 0, instruction.source1 == 0,
                      instruction.source2 == 0, instruction.control == 0 else {
                    throw VF64ValidationError.invalid("invalid constant at instruction \(index)")
                }
                initialized.insert(instruction.destination)
            case .move:
                try register(instruction.destination, at: index)
                try source(instruction.source0, at: index)
                guard instruction.source1 == 0, instruction.source2 == 0,
                      instruction.control == 0, instruction.immediate == 0 else {
                    throw VF64ValidationError.invalid("invalid move at instruction \(index)")
                }
                initialized.insert(instruction.destination)
            case .select:
                try register(instruction.destination, at: index)
                try source(instruction.source0, at: index)
                try source(instruction.source1, at: index)
                try source(instruction.source2, at: index)
                guard instruction.control == 0, instruction.immediate == 0 else {
                    throw VF64ValidationError.invalid("invalid select at instruction \(index)")
                }
                initialized.insert(instruction.destination)
            case .flagsGet, .laneU64:
                try register(instruction.destination, at: index)
                guard instruction.source0 == 0, instruction.source1 == 0,
                      instruction.source2 == 0, instruction.control == 0,
                      instruction.immediate == 0 else {
                    throw VF64ValidationError.invalid("invalid nullary instruction at \(index)")
                }
                initialized.insert(instruction.destination)
            case .add, .sub, .mul, .div, .sqrt, .fma:
                try register(instruction.destination, at: index)
                try source(instruction.source0, at: index)
                if op != .sqrt { try source(instruction.source1, at: index) }
                if op == .fma { try source(instruction.source2, at: index) }
                let decoded = try control(instruction.control, at: index)
                guard !decoded.2, instruction.immediate == 0,
                      (decoded.1 == 0 || decoded.0 == 0),
                      (op != .sqrt || (instruction.source1 == 0 && instruction.source2 == 0)),
                      (op == .fma || instruction.source2 == 0) else {
                    throw VF64ValidationError.invalid("invalid arithmetic control at \(index)")
                }
                initialized.insert(instruction.destination)
            case .remainder, .eq, .le, .lt, .eqSignaling, .leQuiet, .ltQuiet:
                try register(instruction.destination, at: index)
                try source(instruction.source0, at: index)
                try source(instruction.source1, at: index)
                guard instruction.control == 0, instruction.immediate == 0,
                      instruction.source2 == 0 else {
                    throw VF64ValidationError.invalid("invalid semantic instruction at \(index)")
                }
                initialized.insert(instruction.destination)
            case .roundToInt:
                try register(instruction.destination, at: index)
                try source(instruction.source0, at: index)
                let decoded = try control(instruction.control, at: index)
                guard decoded.1 == 0, instruction.immediate == 0,
                      instruction.source1 == 0, instruction.source2 == 0 else {
                    throw VF64ValidationError.invalid("invalid round-to-int at \(index)")
                }
                initialized.insert(instruction.destination)
            case .ui32ToF64, .ui64ToF64, .i32ToF64, .i64ToF64,
                 .f64ToUi32, .f64ToUi64, .f64ToI32, .f64ToI64,
                 .f64ToF32, .f64ToF16, .f32ToF64, .f16ToF64:
                try register(instruction.destination, at: index)
                try source(instruction.source0, at: index)
                let decoded = try control(instruction.control, at: index)
                let allowsExact = [.f64ToUi32, .f64ToUi64, .f64ToI32, .f64ToI64]
                    .contains(op)
                let isWidening = op == .f32ToF64 || op == .f16ToF64
                guard decoded.1 == 0, instruction.immediate == 0,
                      (!decoded.2 || allowsExact),
                      (!isWidening || instruction.control == 0),
                      instruction.source1 == 0, instruction.source2 == 0 else {
                    throw VF64ValidationError.invalid("invalid conversion at \(index)")
                }
                initialized.insert(instruction.destination)
            }
        }
    }
}
