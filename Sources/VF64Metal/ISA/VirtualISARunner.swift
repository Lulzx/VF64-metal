import Foundation

func executeVF64(
    _ harness: MetalHarness, program: VF64Program, inputs: [UInt64]
) throws -> (outputs: [UInt64], flags: [UInt32]) {
    try program.validate()
    let expectedInputs = program.inputSlots * program.laneCount
    guard inputs.count == expectedInputs else {
        throw VF64ValidationError.invalid(
            "VF64 input has \(inputs.count) values; expected \(expectedInputs)"
        )
    }
    let outputCount = program.outputSlots * program.laneCount
    let programBuffer = try harness.buffer(program.words)
    let inputBuffer = try harness.buffer(inputs.isEmpty ? [UInt64(0)] : inputs)
    let outputBuffer = try harness.emptyBuffer(
        count: max(1, outputCount), of: UInt64.self
    )
    let flagsBuffer = try harness.emptyBuffer(
        count: program.laneCount, of: UInt32.self
    )
    try harness.run(
        "vf64_interpreter_kernel", count: program.laneCount,
        buffers: [(0, programBuffer), (1, inputBuffer), (2, outputBuffer),
                  (3, flagsBuffer)], countIndex: 4
    )
    return (
        harness.read(outputBuffer, count: outputCount),
        harness.read(flagsBuffer, count: program.laneCount)
    )
}

func decodeLittleEndian<T: FixedWidthInteger>(
    _ data: Data, as: T.Type
) throws -> [T] {
    guard data.count.isMultiple(of: MemoryLayout<T>.size) else {
        throw VF64ValidationError.invalid("VF64 binary file has a partial word")
    }
    return data.withUnsafeBytes { bytes in
        stride(from: 0, to: data.count, by: MemoryLayout<T>.size).map { offset in
            T(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: T.self))
        }
    }
}

func encodeLittleEndian<T: FixedWidthInteger>(_ values: [T]) -> Data {
    let little = values.map { $0.littleEndian }
    return little.withUnsafeBytes { Data($0) }
}

func runVF64Files(
    _ harness: MetalHarness, programPath: String, inputPath: String,
    outputPath: String, flagsPath: String
) throws {
    let programWords = try decodeLittleEndian(
        Data(contentsOf: URL(fileURLWithPath: programPath)), as: UInt32.self
    )
    let program = try VF64Program.decode(programWords)
    let inputs = try decodeLittleEndian(
        Data(contentsOf: URL(fileURLWithPath: inputPath)), as: UInt64.self
    )
    let result = try executeVF64(harness, program: program, inputs: inputs)
    try encodeLittleEndian(result.outputs).write(
        to: URL(fileURLWithPath: outputPath), options: .atomic
    )
    try encodeLittleEndian(result.flags).write(
        to: URL(fileURLWithPath: flagsPath), options: .atomic
    )
}
