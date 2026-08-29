func runBenchmarks(_ harness: MetalHarness) throws {
    let data = try BenchmarkData(harness: harness)
    print("Device: \(harness.device.name); \(data.count) elements; " +
          "\(data.iterations) dispatches")
    try runStreamingBenchmarks(harness, data: data)
    try runChainBenchmarks(harness, data: data)
    try runAutoPrecisionBenchmarks(harness, data: data)
    try runDotBenchmarks(harness, data: data)
}
