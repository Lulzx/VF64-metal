import Foundation

func validateCodec(_ harness: MetalHarness) throws {
    var rng = SplitMix64(state: 0xf64f64f64)
    var values = (0..<16_384).map { _ in rng.finiteValue(exponentRange: -100...100) }
    values += [0.0, -0.0, .infinity, -.infinity, .nan]
    let input = try harness.buffer(bitsOf(values))
    let first = try harness.emptyBuffer(count: values.count, of: UInt64.self)
    let flags = try harness.emptyBuffer(count: values.count, of: UInt32.self)
    _ = try harness.run(
        "codec_roundtrip", count: values.count,
        buffers: [(0, input), (1, first), (2, flags)], countIndex: 3
    )
    let firstBits: [UInt64] = harness.read(first, count: values.count)

    let secondInput = try harness.buffer(firstBits)
    let second = try harness.emptyBuffer(count: values.count, of: UInt64.self)
    _ = try harness.run(
        "codec_roundtrip", count: values.count,
        buffers: [(0, secondInput), (1, second), (2, flags)], countIndex: 3
    )
    let secondBits: [UInt64] = harness.read(second, count: values.count)
    guard firstBits == secondBits else {
        let mismatch = zip(firstBits, secondBits).enumerated().first {
            $0.element.0 != $0.element.1
        }?.offset ?? -1
        throw HarnessError.validation(
            "pack(unpack(pack(unpack(x)))) was not idempotent at index \(mismatch)"
        )
    }

    let rangeValues: [Double] = [
        Double.greatestFiniteMagnitude, Double.leastNormalMagnitude,
        Double.leastNonzeroMagnitude, Foundation.scalbn(1.0, 128),
        Foundation.scalbn(1.0, -127),
        Double(Float.greatestFiniteMagnitude).nextUp,
    ]
    let rangeInput = try harness.buffer(bitsOf(rangeValues))
    let rangeOutput = try harness.emptyBuffer(count: rangeValues.count, of: UInt64.self)
    let rangeFlags = try harness.emptyBuffer(count: rangeValues.count, of: UInt32.self)
    _ = try harness.run(
        "codec_roundtrip", count: rangeValues.count,
        buffers: [(0, rangeInput), (1, rangeOutput), (2, rangeFlags)], countIndex: 3
    )
    let observedFlags: [UInt32] = harness.read(rangeFlags, count: rangeValues.count)
    guard observedFlags.allSatisfy({ $0 == 1 }) else {
        throw HarnessError.validation("out-of-FP32-range binary64 input was not flagged")
    }

    let decoded = firstBits.map(Double.init(bitPattern:))
    let scores = zip(decoded.prefix(values.count - 5), values.prefix(values.count - 5))
        .map { accuracyBits(got: $0.0, reference: $0.1) }.sorted()
    guard percentile(scores, 0.01) >= 46 else {
        throw HarnessError.validation("codec retained fewer than 46 bits at p01")
    }
    print(String(
        format: "codec       idempotent; precision bits p01 %.2f, median %.2f",
        percentile(scores, 0.01), percentile(scores, 0.5)
    ))
}
