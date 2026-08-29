import Foundation

private final class TestFloatLineReader {
    private let handle: FileHandle
    private var buffered = Data()
    private var reachedEOF = false

    init(_ handle: FileHandle) { self.handle = handle }

    func next() -> String? {
        while true {
            if let newline = buffered.firstIndex(of: 0x0a) {
                let line = buffered[..<newline]
                buffered.removeSubrange(...newline)
                return String(decoding: line, as: UTF8.self)
            }
            if reachedEOF {
                guard !buffered.isEmpty else { return nil }
                defer { buffered.removeAll() }
                return String(decoding: buffered, as: UTF8.self)
            }
            do {
                if let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
                    buffered.append(chunk)
                } else {
                    reachedEOF = true
                }
            } catch {
                reachedEOF = true
            }
        }
    }
}

private struct TestFloatConfiguration {
    let function: String
    let rounding: String
    let exact: Bool

    var generatorArguments: [String] {
        var result = ["-seed", "1", "-level", "1"]
        let roundingIndependent = [
            "f64_eq", "f64_le", "f64_lt", "f64_eq_signaling",
            "f64_le_quiet", "f64_lt_quiet", "f64_rem", "f32_to_f64",
            "f16_to_f64",
        ].contains(function)
        if !roundingIndependent { result.append("-\(rounding)") }
        if function == "f64_roundToInt" || function.hasPrefix("f64_to_ui") ||
            function.hasPrefix("f64_to_i") {
            result.append(exact ? "-exact" : "-notexact")
        }
        result.append(function)
        return result
    }
}

private func vf64TestFloatConfigurations() -> [TestFloatConfiguration] {
    let roundings = ["rnear_even", "rminMag", "rmin", "rmax", "rnear_maxMag"]
    var result: [TestFloatConfiguration] = []
    for rounding in roundings {
        for function in [
            "f64_add", "f64_sub", "f64_mul", "f64_div", "f64_sqrt",
            "f64_mulAdd",
        ] {
            result.append(TestFloatConfiguration(
                function: function, rounding: rounding, exact: false
            ))
        }
    }
    for function in [
        "f64_eq", "f64_le", "f64_lt", "f64_eq_signaling",
        "f64_le_quiet", "f64_lt_quiet", "f64_rem",
    ] {
        result.append(TestFloatConfiguration(
            function: function, rounding: "rnear_even", exact: false
        ))
    }
    for rounding in roundings {
        for exact in [false, true] {
            result.append(TestFloatConfiguration(
                function: "f64_roundToInt", rounding: rounding, exact: exact
            ))
        }
        for function in ["ui32_to_f64", "ui64_to_f64", "i32_to_f64", "i64_to_f64"] {
            result.append(TestFloatConfiguration(
                function: function, rounding: rounding, exact: false
            ))
        }
        for function in ["f64_to_ui32", "f64_to_ui64", "f64_to_i32", "f64_to_i64"] {
            for exact in [false, true] {
                result.append(TestFloatConfiguration(
                    function: function, rounding: rounding, exact: exact
                ))
            }
        }
        for function in ["f64_to_f32", "f64_to_f16"] {
            result.append(TestFloatConfiguration(
                function: function, rounding: rounding, exact: false
            ))
        }
    }
    for function in ["f32_to_f64", "f16_to_f64"] {
        result.append(TestFloatConfiguration(
            function: function, rounding: "rnear_even", exact: false
        ))
    }
    return result
}

func runVF64TestFloatSuite(_ harness: MetalHarness, toolsDirectory: String) throws {
    let generator = URL(fileURLWithPath: toolsDirectory)
        .appendingPathComponent("testfloat_gen")
    guard FileManager.default.isExecutableFile(atPath: generator.path) else {
        throw VF64ValidationError.invalid(
            "testfloat_gen was not found at \(generator.path)"
        )
    }
    for configuration in vf64TestFloatConfigurations() {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = generator
        process.arguments = configuration.generatorArguments
        process.standardOutput = pipe
        process.standardError = FileHandle.standardError
        try process.run()
        let reader = TestFloatLineReader(pipe.fileHandleForReading)
        do {
            try runTestFloatResultConformance(
                harness, function: configuration.function,
                rounding: configuration.rounding, exact: configuration.exact,
                viaISA: true, inputLine: reader.next
            )
        } catch {
            process.terminate()
            process.waitUntilExit()
            throw error
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw VF64ValidationError.invalid(
                "testfloat_gen exited \(process.terminationStatus) for " +
                configuration.function
            )
        }
    }
}
