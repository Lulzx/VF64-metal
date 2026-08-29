import Foundation

private func usage() {
    print("Usage: f64-metal [validate|bench|all|testfloat|testfloat-isa <function> <rounding> [exact]|testfloat-suite-isa <tools-directory>|vf64-run <program.bin> <input.bin> <output.bin> <flags.bin>]")
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
    case "testfloat", "testfloat-isa":
        guard CommandLine.arguments.count >= 4 else {
            usage()
            exit(2)
        }
        try runTestFloatResultConformance(
            harness,
            function: CommandLine.arguments[2],
            rounding: CommandLine.arguments[3],
            exact: CommandLine.arguments.count >= 5 &&
                CommandLine.arguments[4] == "exact",
            viaISA: command == "testfloat-isa"
        )
    case "vf64-run":
        guard CommandLine.arguments.count == 6 else {
            usage()
            exit(2)
        }
        try runVF64Files(
            harness,
            programPath: CommandLine.arguments[2],
            inputPath: CommandLine.arguments[3],
            outputPath: CommandLine.arguments[4],
            flagsPath: CommandLine.arguments[5]
        )
    case "testfloat-suite-isa":
        guard CommandLine.arguments.count == 3 else {
            usage()
            exit(2)
        }
        try runVF64TestFloatSuite(
            harness, toolsDirectory: CommandLine.arguments[2]
        )
    default:
        usage()
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
