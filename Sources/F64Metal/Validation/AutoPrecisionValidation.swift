import Foundation

func validateAutoPrecision(_ harness: MetalHarness) throws {
    let source = """
    kernel mixed(double a, double b, double y) -> double {
        let product: double = a * b;
        return product + y;
    }
    """
    let lanes = 64
    let a = (0..<lanes).map { Double(($0 % 7) + 1) * 0.25 }
    let b = (0..<lanes).map { Double(($0 % 5) + 1) * 0.5 }
    let y = (0..<lanes).map { _ in Foundation.scalbn(0.75, 400) }
    let inputs = bitsOf(a) + bitsOf(b) + bitsOf(y)

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "vf64-auto-\(UUID().uuidString)", isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let inputURL = directory.appendingPathComponent("input.bin")
    let profileURL = directory.appendingPathComponent("profile.json")
    try encodeLittleEndian(inputs).write(to: inputURL)
    try profileVF64Inputs(
        inputPath: inputURL.path, outputPath: profileURL.path,
        slots: 3, laneCount: lanes
    )
    let profile = try JSONDecoder().decode(
        VF64InputProfile.self, from: Data(contentsOf: profileURL)
    )

    var compiler = VF64SourceCompiler(mode: .ieee64, laneCount: lanes)
    let base = try compiler.compile(source)
    let mixed = try selectVF64Precision(
        program: base, profile: profile, requiredAccuracyBits: 44
    )
    guard mixed.1.modeCounts["fast48"] == 1,
          mixed.1.modeCounts["wide48"] == 1 else {
        throw HarnessError.validation(
            "auto policy did not produce the expected fast48/wide48 mix"
        )
    }
    let execution = try executeVF64(
        harness, program: mixed.0, inputs: inputs
    )
    let references = zip(zip(a, b), y).map { $0.0.0 * $0.0.1 + $0.1 }
    let scores = zip(execution.outputs, references).map {
        accuracyBits(got: Double(bitPattern: $0.0), reference: $0.1)
    }.sorted()
    guard percentile(scores, 0.01) >= 44 else {
        throw HarnessError.validation("auto mixed execution missed 44-bit contract")
    }

    let strict = try selectVF64Precision(
        program: base, profile: profile, requiredAccuracyBits: 45
    )
    guard strict.1.modeCounts["ieee64"] == 2 else {
        throw HarnessError.validation(
            "auto policy did not route a strict contract through ieee64"
        )
    }
    print("vf64-auto   profiled mixed fast48/wide48 met 44 bits; strict used ieee64")
}
