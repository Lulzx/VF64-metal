import Foundation
import Metal

struct BenchmarkData {
    let count: Int
    let iterations: Int
    let aBuffer: MTLBuffer
    let bBuffer: MTLBuffer
    let cBuffer: MTLBuffer
    let output: MTLBuffer
    let flags: MTLBuffer
    let alpha: MTLBuffer
    let pairA: MTLBuffer
    let pairB: MTLBuffer
    let pairOutput: MTLBuffer
    let chainA: MTLBuffer
    let chainB: MTLBuffer
    let chainAValues: [Double]
    let chainBValues: [Double]

    init(harness: MetalHarness, count: Int = 1 << 20, iterations: Int = 20) throws {
        self.count = count
        self.iterations = iterations
        var rng = SplitMix64(state: 0x0123456789abcdef)
        let a = (0..<count).map { _ in rng.finiteValue(exponentRange: -20...20) }
        let b = (0..<count).map { _ in rng.finiteValue(exponentRange: -20...20) }
        let c = (0..<count).map { _ in rng.finiteValue(exponentRange: -20...20) }
        aBuffer = try harness.buffer(bitsOf(a))
        bBuffer = try harness.buffer(bitsOf(b))
        cBuffer = try harness.buffer(bitsOf(c))
        output = try harness.emptyBuffer(count: count, of: UInt64.self)
        flags = try harness.emptyBuffer(count: count, of: UInt32.self)
        alpha = try harness.buffer([Double(0.75).bitPattern])
        pairA = try harness.buffer(splitPairs(a))
        pairB = try harness.buffer(splitPairs(b))
        pairOutput = try harness.emptyBuffer(count: count, of: SIMD2<Float>.self)
        chainAValues = (0..<count).map { _ in 0.75 + 0.5 * rng.unit() }
        chainBValues = (0..<count).map { _ in 1.0 + 0.002 * (rng.unit() - 0.5) }
        chainA = try harness.buffer(splitPairs(chainAValues))
        chainB = try harness.buffer(splitPairs(chainBValues))
    }
}

