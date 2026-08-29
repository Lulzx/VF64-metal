import Foundation

private func vf64Instruction(
    _ opcode: VF64Opcode, destination: UInt32 = 0,
    source0: UInt32 = 0, source1: UInt32 = 0, source2: UInt32 = 0,
    control: UInt32 = 0, immediate: UInt64 = 0
) -> VF64Instruction {
    VF64Instruction(
        opcode: opcode, destination: destination, source0: source0,
        source1: source1, source2: source2, control: control,
        immediate: immediate
    )
}

func validateVirtualISA(_ harness: MetalHarness) throws {
    let lanes = 64
    var instructions: [VF64Instruction] = [vf64Instruction(.nop)]
    var expectedSlots: [[UInt64]] = []

    func store(_ register: UInt32, expected: [UInt64]) {
        let slot = expectedSlots.count
        expectedSlots.append(expected)
        instructions.append(vf64Instruction(
            .store, source0: register, immediate: UInt64(slot)
        ))
    }
    func repeated(_ value: UInt64) -> [UInt64] {
        Array(repeating: value, count: lanes)
    }
    func arithmetic(
        _ opcode: VF64Opcode, _ expected: Double,
        mode: VF64PrecisionMode = .ieee64,
        source0: UInt32 = 0, source1: UInt32 = 1, source2: UInt32 = 2
    ) {
        instructions.append(vf64Instruction(
            opcode, destination: 3, source0: source0,
            source1: opcode == .sqrt ? 0 : source1,
            source2: opcode == .fma ? source2 : 0,
            control: VF64Instruction.control(mode: mode)
        ))
        store(3, expected: repeated(expected.bitPattern))
    }

    let a = 1.5
    let b = 2.0
    let c = 0.5
    instructions += [
        vf64Instruction(.load, destination: 0, immediate: 0),
        vf64Instruction(.load, destination: 1, immediate: 1),
        vf64Instruction(.load, destination: 2, immediate: 2),
        vf64Instruction(.move, destination: 3, source0: 0),
    ]
    store(3, expected: repeated(a.bitPattern))
    instructions.append(vf64Instruction(.constant, destination: 4, immediate: 1))
    instructions.append(vf64Instruction(
        .select, destination: 3, source0: 4, source1: 0, source2: 1
    ))
    store(3, expected: repeated(a.bitPattern))
    instructions.append(vf64Instruction(.laneU64, destination: 3))
    store(3, expected: (0..<lanes).map(UInt64.init))

    arithmetic(.add, a + b)
    arithmetic(.add, a + b, mode: .fast48)
    arithmetic(.add, a + b, mode: .wide48)
    arithmetic(.sub, a - b)
    arithmetic(.mul, a * b)
    arithmetic(.div, a / b)
    instructions.append(vf64Instruction(
        .constant, destination: 4, immediate: Double(4).bitPattern
    ))
    arithmetic(.sqrt, 2, source0: 4, source1: 0, source2: 0)
    arithmetic(.sqrt, 2, mode: .fast48, source0: 4, source1: 0, source2: 0)
    arithmetic(.sqrt, 2, mode: .wide48, source0: 4, source1: 0, source2: 0)
    arithmetic(.fma, c.addingProduct(a, b))
    arithmetic(.fma, c.addingProduct(a, b), mode: .fast48)
    arithmetic(.fma, c.addingProduct(a, b), mode: .wide48)
    arithmetic(.remainder, a.remainder(dividingBy: b))
    instructions.append(vf64Instruction(
        .roundToInt, destination: 3, source0: 0,
        control: VF64Instruction.control(rounding: 0, exact: true)
    ))
    store(3, expected: repeated(Double(2).bitPattern))

    let comparisons: [(VF64Opcode, UInt64)] = [
        (.eq, 0), (.le, 1), (.lt, 1), (.eqSignaling, 0),
        (.leQuiet, 1), (.ltQuiet, 1),
    ]
    for (opcode, expected) in comparisons {
        instructions.append(vf64Instruction(
            opcode, destination: 3, source0: 0, source1: 1
        ))
        store(3, expected: repeated(expected))
    }

    let rawU32: UInt64 = 42
    let rawU64: UInt64 = 42
    let rawI32 = UInt64(UInt32(bitPattern: -42))
    let rawI64 = UInt64(bitPattern: -42)
    let integerInputs: [(VF64Opcode, UInt64, UInt64)] = [
        (.ui32ToF64, rawU32, Double(42).bitPattern),
        (.ui64ToF64, rawU64, Double(42).bitPattern),
        (.i32ToF64, rawI32, Double(-42).bitPattern),
        (.i64ToF64, rawI64, Double(-42).bitPattern),
    ]
    for (opcode, raw, expected) in integerInputs {
        instructions.append(vf64Instruction(.constant, destination: 4, immediate: raw))
        instructions.append(vf64Instruction(
            opcode, destination: 3, source0: 4,
            control: VF64Instruction.control()
        ))
        store(3, expected: repeated(expected))
    }

    instructions.append(vf64Instruction(
        .constant, destination: 4, immediate: Double(42).bitPattern
    ))
    let integerOutputs: [(VF64Opcode, UInt64)] = [
        (.f64ToUi32, 42), (.f64ToUi64, 42),
        (.f64ToI32, 42), (.f64ToI64, 42),
    ]
    for (opcode, expected) in integerOutputs {
        instructions.append(vf64Instruction(
            opcode, destination: 3, source0: 4,
            control: VF64Instruction.control(exact: true)
        ))
        store(3, expected: repeated(expected))
    }

    let f32Bits = UInt64(Float(a).bitPattern)
    let f16Bits = UInt64(Float16(a).bitPattern)
    let formats: [(VF64Opcode, UInt64, UInt64)] = [
        (.f64ToF32, a.bitPattern, f32Bits),
        (.f64ToF16, a.bitPattern, f16Bits),
        (.f32ToF64, f32Bits, a.bitPattern),
        (.f16ToF64, f16Bits, a.bitPattern),
    ]
    for (opcode, raw, expected) in formats {
        instructions.append(vf64Instruction(.constant, destination: 4, immediate: raw))
        instructions.append(vf64Instruction(
            opcode, destination: 3, source0: 4,
            control: opcode == .f32ToF64 || opcode == .f16ToF64
                ? 0 : VF64Instruction.control()
        ))
        store(3, expected: repeated(expected))
    }

    instructions.append(vf64Instruction(.flagsClear))
    instructions.append(vf64Instruction(.constant, destination: 4, immediate: 0))
    instructions.append(vf64Instruction(
        .div, destination: 3, source0: 0, source1: 4,
        control: VF64Instruction.control()
    ))
    instructions.append(vf64Instruction(.flagsGet, destination: 3))
    store(3, expected: repeated(8))
    instructions.append(vf64Instruction(.flagsClear))
    instructions.append(vf64Instruction(.halt))

    let program = VF64Program(
        registerCount: 5, inputSlots: 3, outputSlots: expectedSlots.count,
        laneCount: lanes, instructions: instructions
    )
    try program.validate()
    let decoded = try VF64Program.decode(program.words)
    guard decoded.words == program.words else {
        throw HarnessError.validation("VF64 encode/decode was not stable")
    }

    let inputValues = repeated(a.bitPattern) + repeated(b.bitPattern) +
        repeated(c.bitPattern)
    let execution = try executeVF64(
        harness, program: program, inputs: inputValues
    )
    let observed = execution.outputs
    let expected = expectedSlots.flatMap { $0 }
    guard observed == expected else {
        let mismatch = zip(observed, expected).enumerated().first {
            $0.element.0 != $0.element.1
        }?.offset ?? -1
        throw HarnessError.validation(
            "VF64 interpreter mismatch at flat output index \(mismatch)"
        )
    }
    let finalFlags = execution.flags
    guard finalFlags.allSatisfy({ $0 == 0 }) else {
        throw HarnessError.validation("VF64 flags_clear did not clear sticky state")
    }

    var invalidMagic = program.words
    invalidMagic[0] = 0
    var invalidOpcode = program.words
    invalidOpcode[VF64Program.headerWords] = 0xffff
    let uninitialized = VF64Program(
        registerCount: 2, inputSlots: 0, outputSlots: 0, laneCount: 1,
        instructions: [vf64Instruction(.move, destination: 0, source0: 1)]
    ).words
    let reducedDirected = VF64Program(
        registerCount: 2, inputSlots: 1, outputSlots: 0, laneCount: 1,
        instructions: [
            vf64Instruction(.load, destination: 0, immediate: 0),
            vf64Instruction(
                .sqrt, destination: 1, source0: 0,
                control: VF64Instruction.control(rounding: 2, mode: .fast48)
            ),
        ]
    ).words
    for bad in [invalidMagic, invalidOpcode, uninitialized, reducedDirected] {
        do {
            _ = try VF64Program.decode(bad)
            throw HarnessError.validation("VF64 negative validation unexpectedly passed")
        } catch is VF64ValidationError {
            continue
        }
    }
    let covered = Set(instructions.map(\.opcode))
    guard covered == Set(VF64Opcode.allCases) else {
        let missing = Set(VF64Opcode.allCases).subtracting(covered)
        throw HarnessError.validation("VF64 opcode coverage missing \(missing)")
    }

    let fileProgram = VF64Program(
        registerCount: 1, inputSlots: 1, outputSlots: 1, laneCount: 4,
        instructions: [
            vf64Instruction(.load, destination: 0, immediate: 0),
            vf64Instruction(.store, source0: 0, immediate: 0),
            vf64Instruction(.halt),
        ]
    )
    let fileInputs = [UInt64(11), 22, 33, 44]
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "vf64-validation-\(UUID().uuidString)", isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let programURL = directory.appendingPathComponent("program.bin")
    let inputURL = directory.appendingPathComponent("input.bin")
    let outputURL = directory.appendingPathComponent("output.bin")
    let flagsURL = directory.appendingPathComponent("flags.bin")
    try encodeLittleEndian(fileProgram.words).write(to: programURL)
    try encodeLittleEndian(fileInputs).write(to: inputURL)
    try runVF64Files(
        harness, programPath: programURL.path, inputPath: inputURL.path,
        outputPath: outputURL.path, flagsPath: flagsURL.path
    )
    let fileOutputs = try decodeLittleEndian(
        Data(contentsOf: outputURL), as: UInt64.self
    )
    let fileFlags = try decodeLittleEndian(
        Data(contentsOf: flagsURL), as: UInt32.self
    )
    guard fileOutputs == fileInputs, fileFlags == [0, 0, 0, 0] else {
        throw HarnessError.validation("VF64 standalone file runner mismatch")
    }
    print("vf64-isa    all 36 opcodes; 64 lanes; positive/negative gates passed")
}
