import Foundation

func runDotBenchmarks(_ harness: MetalHarness, data: BenchmarkData) throws {
    _ = try harness.dot(a: data.aBuffer, b: data.bBuffer, count: data.count)
    let parallelSeconds = try medianTime {
        try harness.dot(a: data.aBuffer, b: data.bBuffer, count: data.count).1
    }
    print(String(
        format: "dot-4acc    %10.1f", Double(data.count) / parallelSeconds / 1.0e6
    ))

    _ = try harness.dot(
        a: data.aBuffer, b: data.bBuffer, count: data.count,
        firstKernel: "dot_partial_serial_kernel"
    )
    let serialSeconds = try medianTime {
        try harness.dot(
            a: data.aBuffer, b: data.bBuffer, count: data.count,
            firstKernel: "dot_partial_serial_kernel"
        ).1
    }
    print(String(
        format: "dot-serial  %10.1f", Double(data.count) / serialSeconds / 1.0e6
    ))
}

