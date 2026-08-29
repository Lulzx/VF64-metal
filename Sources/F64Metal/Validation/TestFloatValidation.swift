import Foundation

private struct TestFloatBinaryCase {
    let a: UInt64
    let b: UInt64
    let expected: UInt64
    let expectedFlags: UInt8
}

private func parseHex<T: FixedWidthInteger>(_ text: Substring, as: T.Type) -> T? {
    T(text, radix: 16)
}

private func resultsMatch(observed: UInt64, expected: UInt64) -> Bool {
    if Double(bitPattern: expected).isNaN {
        // M1 compares NaNs by class. Payload, signaling, and invalid-flag
        // semantics remain an explicit M2 gate.
        return Double(bitPattern: observed).isNaN
    }
    return observed == expected
}

func runTestFloatResultConformance(
    _ harness: MetalHarness,
    function: String,
    rounding: String,
    batchSize: Int = 65_536
) throws {
    let kernel: String
    switch function {
    case "f64_add": kernel = "soft_add_round_kernel"
    case "f64_sub": kernel = "soft_sub_round_kernel"
    case "f64_mul": kernel = "soft_mul_round_kernel"
    default:
        throw HarnessError.validation(
            "TestFloat function \(function) is not implemented; supported: f64_add, f64_sub, f64_mul"
        )
    }
    let roundingModes: [String: UInt32] = [
        "rnear_even": 0,
        "rminMag": 1,
        "rmin": 2,
        "rmax": 3,
        "rnear_maxMag": 4,
    ]
    guard let roundingMode = roundingModes[rounding] else {
        throw HarnessError.validation(
            "unknown rounding mode \(rounding); supported: " +
            roundingModes.keys.sorted().joined(separator: ", ")
        )
    }
    let roundingBuffer = try harness.buffer([roundingMode])

    var batch: [TestFloatBinaryCase] = []
    batch.reserveCapacity(batchSize)
    var total = 0
    var malformed = 0
    var mismatches: [String] = []
    var expectedFlagged = 0

    func validateBatch(_ cases: [TestFloatBinaryCase]) throws {
        guard !cases.isEmpty else { return }
        let aBuffer = try harness.buffer(cases.map(\.a))
        let bBuffer = try harness.buffer(cases.map(\.b))
        let output = try harness.emptyBuffer(count: cases.count, of: UInt64.self)
        _ = try harness.run(
            kernel,
            count: cases.count,
            buffers: [(0, aBuffer), (1, bBuffer), (2, output), (4, roundingBuffer)],
            countIndex: 3
        )
        let observed: [UInt64] = harness.read(output, count: cases.count)
        for index in cases.indices where !resultsMatch(
            observed: observed[index], expected: cases[index].expected
        ) {
            if mismatches.count < 20 {
                mismatches.append(String(
                    format: "case %d: a=%016llx b=%016llx got=%016llx want=%016llx flags=%02x",
                    total + index,
                    cases[index].a,
                    cases[index].b,
                    observed[index],
                    cases[index].expected,
                    cases[index].expectedFlags
                ))
            }
        }
    }

    while let line = readLine() {
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count == 4,
              let a = parseHex(fields[0], as: UInt64.self),
              let b = parseHex(fields[1], as: UInt64.self),
              let expected = parseHex(fields[2], as: UInt64.self),
              let flags = parseHex(fields[3], as: UInt8.self) else {
            malformed += 1
            continue
        }
        batch.append(TestFloatBinaryCase(
            a: a, b: b, expected: expected, expectedFlags: flags
        ))
        if flags != 0 { expectedFlagged += 1 }
        if batch.count == batchSize {
            try validateBatch(batch)
            total += batch.count
            batch.removeAll(keepingCapacity: true)
        }
    }
    try validateBatch(batch)
    total += batch.count

    guard malformed == 0 else {
        throw HarnessError.validation("TestFloat input contained \(malformed) malformed lines")
    }
    guard total > 0 else {
        throw HarnessError.validation("TestFloat input contained no cases")
    }
    guard mismatches.isEmpty else {
        throw HarnessError.validation(
            "\(function) TestFloat result mismatches:\n" + mismatches.joined(separator: "\n")
        )
    }
    print(
        "\(function) \(rounding) TestFloat result conformance passed over \(total) cases; " +
        "NaNs compared by class; exception flags not checked " +
        "(\(expectedFlagged) oracle cases raised flags)"
    )
}
