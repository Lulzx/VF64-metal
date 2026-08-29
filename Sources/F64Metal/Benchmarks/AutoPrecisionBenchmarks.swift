import Foundation

private func timeVF64Program(
    _ harness: MetalHarness, program: VF64Program, inputs: [UInt64],
    trials: Int = 5
) throws -> Double {
    let programBuffer = try harness.buffer(program.words)
    let inputBuffer = try harness.buffer(inputs)
    let outputBuffer = try harness.emptyBuffer(
        count: program.outputSlots * program.laneCount, of: UInt64.self
    )
    let flagsBuffer = try harness.emptyBuffer(
        count: program.laneCount, of: UInt32.self
    )
    let buffers = [
        (0, programBuffer), (1, inputBuffer), (2, outputBuffer),
        (3, flagsBuffer),
    ]
    _ = try harness.run(
        "vf64_interpreter_kernel", count: program.laneCount,
        buffers: buffers, countIndex: 4
    )
    return try medianTime(trials: trials) {
        try harness.run(
            "vf64_interpreter_kernel", count: program.laneCount,
            buffers: buffers, countIndex: 4
        )
    }
}

func runAutoPrecisionBenchmarks(
    _ harness: MetalHarness, data: BenchmarkData
) throws {
    var lines = ["kernel mixed_chain(double value, double factor) -> double {"]
    for index in 0..<22 {
        let input = index == 0 ? "value" : "v\(index - 1)"
        lines.append("    let v\(index): double = \(input) * factor;")
    }
    lines.append("    return v21;")
    lines.append("}")
    let source = lines.joined(separator: "\n")
    let values = data.chainAValues.map { Foundation.scalbn($0, 110) }
    let factors = data.chainBValues.map { $0 * 2.0 }
    let inputs = bitsOf(values) + bitsOf(factors)
    var compiler = VF64SourceCompiler(mode: .ieee64, laneCount: data.count)
    let ieee = try compiler.compile(source)
    let profile = VF64InputProfile(
        schemaVersion: 1, laneCount: data.count,
        slots: [
            VF64ExponentInterval(minimum: 109, maximum: 110, finiteOnly: true),
            VF64ExponentInterval(minimum: 0, maximum: 1, finiteOnly: true),
        ]
    )
    let automatic = try selectVF64Precision(
        program: ieee, profile: profile, requiredAccuracyBits: 40
    ).0
    let automaticResult = try executeVF64(
        harness, program: automatic, inputs: inputs
    )
    let references = zip(values, factors).map { pair in
        var result = pair.0
        for _ in 0..<22 { result *= pair.1 }
        return result
    }
    let scores = zip(automaticResult.outputs, references).map {
        accuracyBits(got: Double(bitPattern: $0.0), reference: $0.1)
    }.sorted()
    let p01 = percentile(scores, 0.01)
    guard p01 >= 40 else {
        throw HarnessError.validation(
            "benchmarked auto region p01 \(p01) missed its 40-bit contract"
        )
    }
    let ieeeSeconds = try timeVF64Program(harness, program: ieee, inputs: inputs)
    let autoSeconds = try timeVF64Program(
        harness, program: automatic, inputs: inputs
    )
    let operations = Double(data.count * 22)
    let ieeeRate = operations / ieeeSeconds / 1.0e6
    let autoRate = operations / autoSeconds / 1.0e6
    print(String(
        format: "vf64-ieee   %10.1f Mops/s\nvf64-auto   %10.1f Mops/s; %.2fx; p01 %.2f bits",
        ieeeRate, autoRate, autoRate / ieeeRate, p01
    ))
}
