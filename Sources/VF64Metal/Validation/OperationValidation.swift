import Foundation

func validateOperation(
    _ harness: MetalHarness,
    kernel: String,
    label: String,
    a: [Double],
    b: [Double],
    c: [Double]? = nil,
    reference: (Double, Double, Double) -> Double,
    minimumP01: Double = 43
) throws {
    let aBuffer = try harness.buffer(bitsOf(a))
    let bBuffer = try harness.buffer(bitsOf(b))
    let output = try harness.emptyBuffer(count: a.count, of: UInt64.self)
    var buffers = [(0, aBuffer), (1, bBuffer)]
    var countIndex = 3
    if let c {
        buffers.append((2, try harness.buffer(bitsOf(c))))
        buffers.append((3, output))
        countIndex = 4
    } else {
        buffers.append((2, output))
    }
    _ = try harness.run(
        kernel, count: a.count, buffers: buffers, countIndex: countIndex
    )
    let observed: [UInt64] = harness.read(output, count: a.count)
    var scores: [Double] = []
    scores.reserveCapacity(a.count)
    for index in a.indices {
        let expected = reference(a[index], b[index], c?[index] ?? 0)
        scores.append(accuracyBits(
            got: Double(bitPattern: observed[index]), reference: expected
        ))
    }
    scores.sort()
    let p01 = percentile(scores, 0.01)
    guard p01 >= minimumP01 else {
        throw HarnessError.validation(
            "\(label) precision p01 was \(String(format: "%.2f", p01)) bits"
        )
    }
    print(
        "\(label.padding(toLength: 11, withPad: " ", startingAt: 0)) " +
        "precision bits p01 " +
        String(format: "%.2f, median %.2f", p01, percentile(scores, 0.5))
    )
}

