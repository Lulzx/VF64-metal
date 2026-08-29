import Foundation

private func usage() {
    print("Usage: f64-metal [validate|bench|all|testfloat|testfloat-isa <function> <rounding> [exact]|testfloat-suite-isa <tools-directory>|vf64-compile --fp64=<fast48|wide48|ieee64> --lanes=N <source> <program.bin>|vf64-run <program.bin> <input.bin> <output.bin> <flags.bin>]")
}

do {
    let command = CommandLine.arguments.dropFirst().first ?? "validate"
    if command == "vf64-compile" {
        guard CommandLine.arguments.count == 6,
              CommandLine.arguments[2].hasPrefix("--fp64="),
              CommandLine.arguments[3].hasPrefix("--lanes="),
              let laneCount = Int(CommandLine.arguments[3].dropFirst(8)) else {
            usage()
            exit(2)
        }
        let modeName = String(CommandLine.arguments[2].dropFirst(7))
        let modes: [String: VF64PrecisionMode] = [
            "fast48": .fast48, "wide48": .wide48, "ieee64": .ieee64,
        ]
        guard let mode = modes[modeName] else {
            throw VF64CompilerError.invalid("unknown --fp64 mode '\(modeName)'")
        }
        try compileVF64SourceFile(
            sourcePath: CommandLine.arguments[4],
            outputPath: CommandLine.arguments[5], mode: mode,
            laneCount: laneCount
        )
    } else {
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
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
