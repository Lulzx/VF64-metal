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
    let (aBits, bBits) = softFloatInputs()
    let aBuffer = try harness.buffer(aBits)
    let bBuffer = try harness.buffer(bBits)
    let cases: [(String, String, (Double, Double) -> Double)] = [
        ("exact-add", "soft_add_kernel", +),
        ("exact-sub", "soft_sub_kernel", -),
        ("exact-mul", "soft_mul_kernel", *),
        ("exact-div", "soft_div_kernel", /),
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
