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
    var hypotVectors = m9SmokeVectors["f64_hypot"]!["rnear_even"]!.makeIterator()
    try runWideHypotConformance(harness) {
        guard let vector = hypotVectors.next() else { return nil }
        return String(format: "%016llx %016llx %016llx %02x",
                      vector.0, vector.1, vector.2, vector.3)
    }

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

// Consumes the existing m9_ref f64_hypot/rnear_even vector format. Unlike
// binary64 conformance, this is an accuracy gate for the reduced mode.
func runWideHypotConformance(
    _ harness: MetalHarness, inputLine: () -> String? = { readLine() }
) throws {
    var a: [UInt64] = []
    var b: [UInt64] = []
    var reference: [UInt64] = []
    var total = 0
    var failures = 0
    var worstNormalRelative = 0.0
    var worstSubnormalRelative = 0.0
    var worstSubnormalUlps = 0.0
    let tolerance = 0x1p-44

    func validateBatch() throws {
        guard !a.isEmpty else { return }
        let first = try harness.buffer(a)
        let second = try harness.buffer(b)
        let output = try harness.emptyBuffer(count: a.count, of: UInt64.self)
        try harness.run(
            "wide_hypot_kernel", count: a.count,
            buffers: [(0, first), (1, second), (2, output)], countIndex: 3
        )
        let observed: [UInt64] = harness.read(output, count: a.count)
        for index in a.indices {
            let got = Double(bitPattern: observed[index])
            let want = Double(bitPattern: reference[index])
            var passes: Bool
            if Double(bitPattern: a[index]).isInfinite ||
                    Double(bitPattern: b[index]).isInfinite {
                // Reduced decoding quiets signaling NaNs before arithmetic;
                // the infinity-precedence policy therefore covers them too.
                passes = got == .infinity
            } else if want.isNaN {
                passes = got.isNaN
            } else if want.isInfinite {
                // Input quantization can move a value across the final
                // overflow boundary; the contract permits that top edge.
                passes = got == .infinity ||
                    (got.isFinite && got >= Double.greatestFiniteMagnitude * (1 - tolerance))
            } else if want == 0 {
                passes = observed[index] == 0
            } else if got == .infinity {
                passes = want >= Double.greatestFiniteMagnitude * (1 - tolerance)
            } else {
                let error = abs(got - want)
                let relative = error / want
                if want < Double.leastNormalMagnitude {
                    worstSubnormalRelative = max(worstSubnormalRelative, relative)
                    worstSubnormalUlps = max(
                        worstSubnormalUlps, error / Double.leastNonzeroMagnitude
                    )
                } else {
                    worstNormalRelative = max(worstNormalRelative, relative)
                }
                // The corpus gate permits one binary64 ulp where that is
                // larger than its relative-accuracy budget.
                passes = got.isFinite && got >= 0 &&
                    error <= max(tolerance * want, want.ulp)
            }
            if !passes {
                if failures < 10 {
                    print(String(format: "wide-hypot a=%016llx b=%016llx got=%016llx want=%016llx",
                                 a[index], b[index], observed[index], reference[index]))
                }
                failures += 1
            }
        }
        total += a.count
        a.removeAll(keepingCapacity: true)
        b.removeAll(keepingCapacity: true)
        reference.removeAll(keepingCapacity: true)
    }

    while let line = inputLine() {
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count == 4,
              let first = UInt64(fields[0], radix: 16),
              let second = UInt64(fields[1], radix: 16),
              let expected = UInt64(fields[2], radix: 16),
              UInt8(fields[3], radix: 16) != nil else {
            throw HarnessError.validation("malformed MPFR hypot vector")
        }
        a.append(first)
        b.append(second)
        reference.append(expected)
        if a.count == 65_536 { try validateBatch() }
    }
    try validateBatch()
    print("wide-hypot cases=\(total) failures=\(failures) " +
          "worst_normal_relative=\(worstNormalRelative) " +
          "worst_subnormal_relative=\(worstSubnormalRelative) " +
          "worst_subnormal_ulps=\(worstSubnormalUlps)")
    guard total > 0 && failures == 0 else {
        throw HarnessError.validation("wide48 hypot MPFR accuracy gate failed")
    }
}
