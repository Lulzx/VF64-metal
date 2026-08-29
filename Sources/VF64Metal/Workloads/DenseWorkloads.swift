import Foundation
import Metal

private func gemmReference(a: [Double], b: [Double], dimension: Int) -> [Double] {
    var result = [Double](repeating: 0, count: dimension * dimension)
    for row in 0..<dimension {
        for column in 0..<dimension {
            var accumulator = 0.0
            for k in 0..<dimension {
                accumulator.addProduct(
                    a[row * dimension + k], b[k * dimension + column]
                )
            }
            result[row * dimension + column] = accumulator
        }
    }
    return result
}

func runDenseWorkloads(_ harness: MetalHarness) throws {
    let dimension = 192
    let count = dimension * dimension
    let a = (0..<count).map { index in
        sin(Double((index * 17) % 4093) * 0.0031) * 0.125
    }
    let b = (0..<count).map { index in
        cos(Double((index * 29) % 4099) * 0.0027) * 0.125
    }
    let aBuffer = try harness.buffer(bitsOf(a))
    let bBuffer = try harness.buffer(bitsOf(b))
    let dimensionBuffer = try harness.buffer([UInt32(dimension)])
    let output = try harness.emptyBuffer(count: count, of: UInt64.self)
    let buffers: [(Int, MTLBuffer)] = [
        (0, aBuffer), (1, bBuffer), (2, output), (3, dimensionBuffer),
    ]
    let cpuStart = ContinuousClock.now
    let reference = gemmReference(a: a, b: b, dimension: dimension)
    let cpuSeconds = cpuStart.duration(to: .now).seconds
    print("\ngemm-square-\(dimension): \(count) outputs; \(dimension * count) fused multiply-adds")
    print(String(format: "cpu-fp64    %8.3f ms", cpuSeconds * 1.0e3))
    let modes: [(String, String)] = [
        ("fp32", "gemm_fp32_kernel"),
        ("fast48", "gemm_fast48_kernel"),
        ("wide48", "gemm_wide48_kernel"),
        ("ieee64", "gemm_ieee64_kernel"),
    ]
    for (name, kernel) in modes {
        try harness.run(kernel, count: count, buffers: buffers, countIndex: 4)
        let seconds = try medianTime(trials: 5) {
            try harness.run(kernel, count: count, buffers: buffers, countIndex: 4)
        }
        let observed: [UInt64] = harness.read(output, count: count)
        let scores = zip(observed, reference).map {
            accuracyBits(got: Double(bitPattern: $0.0), reference: $0.1)
        }.sorted()
        print(String(
            format: "%-8s    %8.3f ms; p01 %5.2f bits; %.2fx CPU",
            (name as NSString).utf8String!, seconds * 1.0e3,
            percentile(scores, 0.01), cpuSeconds / seconds
        ))
    }
}
