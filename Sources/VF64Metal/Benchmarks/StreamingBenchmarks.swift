import Foundation
import Metal

func runStreamingBenchmarks(_ harness: MetalHarness, data: BenchmarkData) throws {
    print("kernel       million elements/s")
    let cases: [(String, String, [(Int, MTLBuffer)], Int)] = [
        ("codec", "codec_roundtrip", [(0, data.aBuffer), (1, data.output), (2, data.flags)], 3),
        ("add", "add_kernel", [(0, data.aBuffer), (1, data.bBuffer), (2, data.output)], 3),
        ("soft-add", "soft_add_kernel", [(0, data.aBuffer), (1, data.bBuffer), (2, data.output)], 3),
        ("wide-add", "wide_add_kernel", [(0, data.aBuffer), (1, data.bBuffer), (2, data.output)], 3),
        ("multiply", "mul_kernel", [(0, data.aBuffer), (1, data.bBuffer), (2, data.output)], 3),
        ("soft-mul", "soft_mul_kernel", [(0, data.aBuffer), (1, data.bBuffer), (2, data.output)], 3),
        ("wide-mul", "wide_mul_kernel", [(0, data.aBuffer), (1, data.bBuffer), (2, data.output)], 3),
        ("mul-short", "mul_short_kernel", [(0, data.aBuffer), (1, data.bBuffer), (2, data.output)], 3),
        ("mul-dekker", "mul_dekker_kernel", [(0, data.aBuffer), (1, data.bBuffer), (2, data.output)], 3),
        ("divide", "div_kernel", [(0, data.aBuffer), (1, data.bBuffer), (2, data.output)], 3),
        ("wide-div", "wide_div_kernel", [(0, data.aBuffer), (1, data.bBuffer), (2, data.output)], 3),
        ("div-1corr", "div_one_kernel", [(0, data.aBuffer), (1, data.bBuffer), (2, data.output)], 3),
        ("fma", "fma_kernel", [(0, data.aBuffer), (1, data.bBuffer), (2, data.cBuffer), (3, data.output)], 4),
        ("wide-fma", "wide_fma_kernel", [(0, data.aBuffer), (1, data.bBuffer), (2, data.cBuffer), (3, data.output)], 4),
        ("axpy", "axpy_kernel", [(0, data.alpha), (1, data.aBuffer), (2, data.bBuffer), (3, data.output)], 4),
    ]
    for (label, kernel, buffers, countIndex) in cases {
        _ = try harness.run(kernel, count: data.count, buffers: buffers, countIndex: countIndex)
        let elapsed = try medianTime {
            try harness.run(
                kernel, count: data.count, buffers: buffers,
                countIndex: countIndex, iterations: data.iterations
            )
        }
        let rate = Double(data.count * data.iterations) / elapsed / 1.0e6
        print(label.padding(toLength: 11, withPad: " ", startingAt: 0) +
              String(format: "%10.1f", rate))
    }

    print("\npair-only arithmetic (codec excluded)")
    let pairCases: [(String, String)] = [
        ("pair-add", "pair_add_kernel"),
        ("pair-mul", "pair_mul_kernel"),
        ("pair-short", "pair_mul_short_kernel"),
        ("pair-dekker", "pair_mul_dekker_kernel"),
        ("pair-div", "pair_div_kernel"),
        ("pair-div1", "pair_div_one_kernel"),
    ]
    for (label, kernel) in pairCases {
        let buffers = [(0, data.pairA), (1, data.pairB), (2, data.pairOutput)]
        _ = try harness.run(kernel, count: data.count, buffers: buffers, countIndex: 3)
        let elapsed = try medianTime {
            try harness.run(
                kernel, count: data.count, buffers: buffers,
                countIndex: 3, iterations: data.iterations
            )
        }
        let rate = Double(data.count * data.iterations) / elapsed / 1.0e6
        print(label.padding(toLength: 11, withPad: " ", startingAt: 0) +
              String(format: "%10.1f", rate))
    }
}
