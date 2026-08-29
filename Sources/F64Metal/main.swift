import Foundation

private func usage() {
    print("Usage: f64-metal [validate|bench|all]")
}

do {
    let command = CommandLine.arguments.dropFirst().first ?? "validate"
    let harness = try MetalHarness()
    switch command {
    case "validate":
        try runValidation(harness)
    case "bench":
        try runBenchmarks(harness)
    case "all":
        try runValidation(harness)
        try runBenchmarks(harness)
    default:
        usage()
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

