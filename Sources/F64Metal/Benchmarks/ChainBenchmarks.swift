import Foundation
import Metal

func runChainBenchmarks(_ harness: MetalHarness, data: BenchmarkData) throws {
    print("\ncompute-bound 32-operation dependency chains (million operations/s)")
    let pairCases: [(String, String)] = [
        ("fma-resid", "pair_mul_chain_kernel"),
        ("short", "pair_mul_short_chain_kernel"),
        ("dekker", "pair_mul_dekker_chain_kernel"),
    ]
    for (label, kernel) in pairCases {
        let buffers = [(0, data.chainA), (1, data.chainB), (2, data.pairOutput)]
        _ = try harness.run(kernel, count: data.count, buffers: buffers, countIndex: 3)
        let elapsed = try medianTime(trials: 3) {
            try harness.run(kernel, count: data.count, buffers: buffers, countIndex: 3)
        }
        let rate = Double(data.count * 32) / elapsed / 1.0e6
        print(label.padding(toLength: 11, withPad: " ", startingAt: 0) +
              String(format: "%10.1f", rate))
    }

    print("\nsoft versus pair 32-operation chains (million operations/s)")
    let softChainA = try harness.buffer(bitsOf(data.chainAValues))
    let softChainB = try harness.buffer(bitsOf(data.chainBValues))
    let cases: [(String, String, [(Int, MTLBuffer)])] = [
        ("pair-add", "pair_add_chain_kernel", [(0, data.chainA), (1, data.chainB), (2, data.pairOutput)]),
        ("soft-add", "soft_add_chain_kernel", [(0, softChainA), (1, softChainB), (2, data.output)]),
        ("pair-mul", "pair_mul_chain_kernel", [(0, data.chainA), (1, data.chainB), (2, data.pairOutput)]),
        ("wide-mul", "wide_mul_chain_kernel", [(0, softChainA), (1, softChainB), (2, data.output)]),
        ("soft-mul", "soft_mul_chain_kernel", [(0, softChainA), (1, softChainB), (2, data.output)]),
    ]
    for (label, kernel, buffers) in cases {
        _ = try harness.run(kernel, count: data.count, buffers: buffers, countIndex: 3)
        let elapsed = try medianTime(trials: 3) {
            try harness.run(kernel, count: data.count, buffers: buffers, countIndex: 3)
        }
        let rate = Double(data.count * 32) / elapsed / 1.0e6
        print(label.padding(toLength: 11, withPad: " ", startingAt: 0) +
              String(format: "%10.1f", rate))
    }
}
