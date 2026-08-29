import Foundation

private func usage() {
    print("Usage: f64-metal [validate|bench|workloads|all|testfloat|testfloat-isa <function> <rounding> [exact]|testfloat-suite-isa <tools-directory>|vf64-profile --slots=N --lanes=N <input.bin> <profile.json>|vf64-compile --fp64=<fast48|wide48|ieee64|auto> --lanes=N [--accuracy-bits=N --profile=FILE --diagnostics=FILE] <source> <program.bin>|vf64-run <program.bin> <input.bin> <output.bin> <flags.bin>]")
}

do {
    let command = CommandLine.arguments.dropFirst().first ?? "validate"
    if command == "vf64-compile" {
        let arguments = Array(CommandLine.arguments.dropFirst(2))
        guard arguments.count >= 4 else {
            usage()
            exit(2)
        }
        let sourcePath = arguments[arguments.count - 2]
        let outputPath = arguments[arguments.count - 1]
        let options = Dictionary(uniqueKeysWithValues: arguments.dropLast(2).compactMap {
            argument -> (String, String)? in
            guard argument.hasPrefix("--"),
                  let separator = argument.firstIndex(of: "=") else { return nil }
            return (String(argument[..<separator]), String(argument[argument.index(after: separator)...]))
        })
        guard let modeName = options["--fp64"],
              let laneText = options["--lanes"],
              let laneCount = Int(laneText) else {
            usage()
            exit(2)
        }
        let modes: [String: VF64PrecisionMode] = [
            "fast48": .fast48, "wide48": .wide48, "ieee64": .ieee64,
        ]
        if modeName == "auto" {
            guard let accuracyText = options["--accuracy-bits"],
                  let accuracy = Int(accuracyText),
                  let profile = options["--profile"],
                  let diagnostics = options["--diagnostics"] else {
                throw VF64CompilerError.invalid(
                    "--fp64=auto requires --accuracy-bits, --profile, and --diagnostics"
                )
            }
            try compileVF64SourceFileAuto(
                sourcePath: sourcePath, outputPath: outputPath,
                diagnosticsPath: diagnostics, profilePath: profile,
                laneCount: laneCount, requiredAccuracyBits: accuracy
            )
        } else {
            guard let mode = modes[modeName] else {
                throw VF64CompilerError.invalid("unknown --fp64 mode '\(modeName)'")
            }
            try compileVF64SourceFile(
                sourcePath: sourcePath, outputPath: outputPath, mode: mode,
                laneCount: laneCount
            )
        }
    } else if command == "vf64-profile" {
        guard CommandLine.arguments.count == 6,
              CommandLine.arguments[2].hasPrefix("--slots="),
              CommandLine.arguments[3].hasPrefix("--lanes="),
              let slots = Int(CommandLine.arguments[2].dropFirst(8)),
              let laneCount = Int(CommandLine.arguments[3].dropFirst(8)) else {
            usage()
            exit(2)
        }
        try profileVF64Inputs(
            inputPath: CommandLine.arguments[4],
            outputPath: CommandLine.arguments[5], slots: slots,
            laneCount: laneCount
        )
    } else {
        let harness = try MetalHarness()
        switch command {
    case "validate":
        try runValidation(harness)
    case "bench":
        try runBenchmarks(harness)
    case "workloads":
        try runScientificWorkloads(harness)
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
