import Foundation

private func softFloatInputs() -> ([UInt64], [UInt64]) {
    var directed: [UInt64] = [
        0x0000000000000000, 0x8000000000000000,
        0x0000000000000001, 0x000fffffffffffff,
        0x0010000000000000, 0x0010000000000001,
        0x3ca0000000000000, 0x3ff0000000000000,
        0x3ff0000000000001, 0x4000000000000000,
        0x7fefffffffffffff, 0xffefffffffffffff,
        0x7ff0000000000000, 0xfff0000000000000,
        0x7ff0000000000001, 0x7ff8000000001234,
    ]
    let exponentFields: [UInt64] = [
        0, 1, 2, 3, 511, 1022, 1023, 1024, 1535, 2045, 2046, 2047,
    ]
    let fractions: [UInt64] = [
        0, 1, 2, 3, (1 << 26) - 1, 1 << 26,
        (1 << 51) - 1, 1 << 51, (1 << 51) + 1,
        0x000ffffffffffffd, 0x000ffffffffffffe, 0x000fffffffffffff,
    ]
    for sign: UInt64 in [0, 1] {
        for exponent in exponentFields {
            for fraction in fractions {
                directed.append((sign << 63) | (exponent << 52) | fraction)
            }
        }
    }
    directed = Array(Set(directed)).sorted()

    var aBits: [UInt64] = []
    var bBits: [UInt64] = []
    for a in directed {
        for b in directed {
            aBits.append(a)
            bBits.append(b)
        }
    }
    var rng = SplitMix64(state: 0x50f7f10a7)
    for _ in 0..<131_072 {
        aBits.append(rng.next())
        bBits.append(rng.next())
    }
    return (aBits, bBits)
}

func validateExactHostOracle(_ harness: MetalHarness) throws {
    try validateReciprocalCoefficients(harness)
    let (aBits, bBits) = softFloatInputs()
    let aBuffer = try harness.buffer(aBits)
    let bBuffer = try harness.buffer(bBits)
    let cases: [(String, String, (Double, Double) -> Double)] = [
        ("exact-add", "soft_add_kernel", +),
        ("exact-sub", "soft_sub_kernel", -),
        ("exact-mul", "soft_mul_kernel", *),
        ("exact-div", "soft_div_kernel", /),
        ("exact-sqrt", "soft_sqrt_kernel", { a, _ in a.squareRoot() }),
    ]
    for (label, kernel, operation) in cases {
        let output = try harness.emptyBuffer(count: aBits.count, of: UInt64.self)
        _ = try harness.run(
            kernel, count: aBits.count,
            buffers: [(0, aBuffer), (1, bBuffer), (2, output)], countIndex: 3
        )
        let observed: [UInt64] = harness.read(output, count: aBits.count)
        for index in aBits.indices {
            let a = Double(bitPattern: aBits[index])
            let b = Double(bitPattern: bBits[index])
            let expected = operation(a, b)
            let got = Double(bitPattern: observed[index])
            let correct = expected.isNaN ? got.isNaN : observed[index] == expected.bitPattern
            if !correct {
                throw HarnessError.validation(String(
                    format: "%@ mismatch at %d: a=%016llx b=%016llx got=%016llx want=%016llx",
                    label, index, aBits[index], bBits[index], observed[index], expected.bitPattern
                ))
            }
        }
        print(
            "\(label.padding(toLength: 11, withPad: " ", startingAt: 0)) " +
            "bit-exact RNE over \(aBits.count) cases"
        )
    }
}

private func validateReciprocalCoefficients(_ harness: MetalHarness) throws {
    let count = 4096
    var rng = SplitMix64(state: 0xc371f1ed)
    var a = [UInt64](), b = [UInt64](), injected = [SIMD4<UInt32>]()
    for i in 0..<count {
        a.append((UInt64(1 + (17 * i) % 2046) << 52)
            | (rng.next() & 0x000fffffffffffff) | (UInt64(i & 1) << 63))
        b.append((UInt64(1 + i % 2046) << 52)
            | (UInt64(i & 15) << 48) | (rng.next() & 0x0000ffffffffffff))
        if i % 31 == 0 { b[i] &= 0x7ff0000000000000 }
        injected.append(SIMD4(UInt32(truncatingIfNeeded: rng.next()),
                              UInt32(truncatingIfNeeded: rng.next()), 0, 0))
    }
    for mode in UInt32(0)...UInt32(2) {
        for i in 0..<count { injected[i].z = mode }
        let output = try harness.emptyBuffer(count: count, of: SIMD2<UInt64>.self)
        let status = try harness.emptyBuffer(count: count, of: UInt32.self)
        _ = try harness.run("soft_div_coefficients_kernel", count: count,
            buffers: [(0, try harness.buffer(a)), (1, try harness.buffer(b)),
                      (2, try harness.buffer(injected)), (3, output), (4, status)], countIndex: 5)
        let values: [SIMD2<UInt64>] = harness.read(output, count: count)
        let flags: [UInt32] = harness.read(status, count: count)
        var accepted = 0, repaired = 0
        for i in 0..<count {
            let expected = (Double(bitPattern: a[i]) / Double(bitPattern: b[i])).bitPattern
            guard values[i].x == expected && values[i].y == expected && flags[i] <= 3 else {
                throw HarnessError.validation("reciprocal coefficients: mode \(mode), case \(i)")
            }
            accepted += Int(flags[i] & 1)
            repaired += Int((flags[i] >> 1) & 1)
        }
        guard mode == 0 ? (accepted == count && repaired > 0) : accepted < count else {
            throw HarnessError.validation("reciprocal certificate path: mode=\(mode) accepted=\(accepted) repaired=\(repaired)")
        }
        print("reciprocal-coefficients mode=\(mode) cases=\(count) accepted=\(accepted) repairs=\(repaired)")
    }
}
