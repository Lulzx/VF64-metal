import Foundation

func validateDot(_ harness: MetalHarness, a: [Double], b: [Double]) throws {
    let aBuffer = try harness.buffer(bitsOf(a))
    let bBuffer = try harness.buffer(bitsOf(b))
    let (observed, _) = try harness.dot(a: aBuffer, b: bBuffer, count: a.count)
    var sum = 0.0
    var correction = 0.0
    for index in a.indices {
        let product = a[index] * b[index]
        let y = product - correction
        let t = sum + y
        correction = (t - sum) - y
        sum = t
    }
    let score = accuracyBits(got: observed, reference: sum)
    guard score >= 42 else {
        throw HarnessError.validation(
            "dot retained only \(String(format: "%.2f", score)) bits"
        )
    }
    print(String(
        format: "dot         4-way/thread compensated reduction: %.2f bits", score
    ))
}

