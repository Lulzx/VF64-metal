import Foundation

func validateSpecialValues(_ harness: MetalHarness) throws {
    let values: [Double] = [0.0, -0.0, 1.0, -1.0, .infinity, -.infinity, .nan]
    var a: [Double] = []
    var b: [Double] = []
    for x in values {
        for y in values {
            a.append(x)
            b.append(y)
        }
    }
    let aBuffer = try harness.buffer(bitsOf(a))
    let bBuffer = try harness.buffer(bitsOf(b))
    let cases: [(String, (Double, Double) -> Double)] = [
        ("add_kernel", +),
        ("mul_kernel", *),
    ]
    for (kernel, operation) in cases {
        let output = try harness.emptyBuffer(count: a.count, of: UInt64.self)
        _ = try harness.run(
            kernel, count: a.count,
            buffers: [(0, aBuffer), (1, bBuffer), (2, output)], countIndex: 3
        )
        let observed: [UInt64] = harness.read(output, count: a.count)
        for index in a.indices {
            let got = Double(bitPattern: observed[index])
            let expected = operation(a[index], b[index])
            if expected.isNaN {
                if !got.isNaN {
                    throw HarnessError.validation("\(kernel) lost NaN semantics")
                }
            } else if got != expected || (got == 0 && got.sign != expected.sign) {
                throw HarnessError.validation(
                    "\(kernel) special mismatch for \(a[index]), \(b[index])"
                )
            }
        }
    }
    print("specials    add/mul NaN, Inf, and signed-zero matrix passed")
}

