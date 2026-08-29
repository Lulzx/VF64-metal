import Foundation

private func wideAccuracySummary(
    _ observed: [UInt64], references: [Double], label: String,
    minimumP01: Double = 44
) throws {
    let scores = zip(observed, references).map {
        accuracyBits(got: Double(bitPattern: $0.0), reference: $0.1)
    }.sorted()
    let p01 = percentile(scores, 0.01)
    let median = percentile(scores, 0.50)
    guard p01 >= minimumP01 else {
        throw HarnessError.validation(
            "\(label) wide48 p01 precision \(p01) below \(minimumP01)"
        )
    }
    print(String(
        format: "%-11s wide48 precision bits p01 %.2f, median %.2f",
        (label as NSString).utf8String!, p01, median
    ))
}

func validateWideMode(_ harness: MetalHarness) throws {
    var rng = SplitMix64(state: 0x5749444534384d33)
    let count = 16_384
    var roundtrip = [
        0.0, -0.0, Double.leastNonzeroMagnitude,
        -Double.leastNonzeroMagnitude, Double.leastNormalMagnitude,
        -Double.leastNormalMagnitude, Double.greatestFiniteMagnitude,
        -Double.greatestFiniteMagnitude,
    ]
    roundtrip += (0..<count).map { _ in
        rng.finiteValue(exponentRange: -1022...1023)
    }
    let roundtripInput = try harness.buffer(bitsOf(roundtrip))
    let roundtripOutput = try harness.emptyBuffer(
        count: roundtrip.count, of: UInt64.self
    )
    try harness.run(
        "wide_roundtrip_kernel", count: roundtrip.count,
        buffers: [(0, roundtripInput), (1, roundtripOutput)], countIndex: 2
    )
    try wideAccuracySummary(
        harness.read(roundtripOutput, count: roundtrip.count),
        references: roundtrip, label: "wide-codec", minimumP01: 46
    )

    let a = (0..<count).map { _ in
        rng.finiteValue(exponentRange: -450...450)
    }
    let b = (0..<count).map { _ in
        rng.finiteValue(exponentRange: -450...450)
    }
    let c = (0..<count).map { _ in
        rng.finiteValue(exponentRange: -450...450)
    }
    let aBuffer = try harness.buffer(bitsOf(a))
    let bBuffer = try harness.buffer(bitsOf(b))
    let cBuffer = try harness.buffer(bitsOf(c))
    let output = try harness.emptyBuffer(count: count, of: UInt64.self)
    let operations: [(String, String, (Double, Double) -> Double)] = [
        ("wide-add", "wide_add_kernel", +),
        ("wide-sub", "wide_sub_kernel", -),
        ("wide-mul", "wide_mul_kernel", *),
        ("wide-div", "wide_div_kernel", /),
    ]
    for (label, kernel, reference) in operations {
        try harness.run(
            kernel, count: count,
            buffers: [(0, aBuffer), (1, bBuffer), (2, output)], countIndex: 3
        )
        try wideAccuracySummary(
            harness.read(output, count: count),
            references: zip(a, b).map(reference), label: label
        )
    }
    try harness.run(
        "wide_fma_kernel", count: count,
        buffers: [(0, aBuffer), (1, bBuffer), (2, cBuffer), (3, output)],
        countIndex: 4
    )
    try wideAccuracySummary(
        harness.read(output, count: count),
        references: zip(zip(a, b), c).map {
            $0.1.addingProduct($0.0.0, $0.0.1)
        },
        label: "wide-fma"
    )
}
