import Foundation

func validateVF64SourceCompiler(_ harness: MetalHarness) throws {
    let source = """
    kernel axpy(double alpha, double x, double y) -> double {
        let product: double = alpha * x;
        return product + y;
    }
    """
    let lanes = 64
    let alpha = Array(repeating: Double(0.75), count: lanes)
    let x = (0..<lanes).map { Double($0 - 31) }
    let y = Array(repeating: Double(0.5), count: lanes)
    let inputs = bitsOf(alpha) + bitsOf(x) + bitsOf(y)
    let expected = zip(zip(alpha, x), y).map {
        ($0.0.0 * $0.0.1 + $0.1).bitPattern
    }

    for mode in [
        VF64PrecisionMode.fast48, .wide48, .ieee64,
    ] {
        var compiler = VF64SourceCompiler(mode: mode, laneCount: lanes)
        let program = try compiler.compile(source)
        let arithmetic = program.instructions.filter {
            [.add, .sub, .mul, .div, .sqrt, .fma].contains($0.opcode)
        }
        guard arithmetic.map(\.opcode) == [.mul, .add],
              arithmetic.allSatisfy({ (($0.control >> 8) & 3) == mode.rawValue }) else {
            throw HarnessError.validation(
                "source compiler did not route arithmetic through \(mode)"
            )
        }
        let result = try executeVF64(harness, program: program, inputs: inputs)
        guard result.outputs == expected, result.flags.allSatisfy({ $0 == 0 }) else {
            throw HarnessError.validation(
                "source compiler \(mode) execution mismatch"
            )
        }
    }

    let fusedSource = """
    kernel fused(double a, double b, double c) -> double {
        return fma(a, b, c);
    }
    """
    var fusedCompiler = VF64SourceCompiler(mode: .ieee64, laneCount: lanes)
    let fused = try fusedCompiler.compile(fusedSource)
    guard fused.instructions.contains(where: { $0.opcode == .fma }) else {
        throw HarnessError.validation("source fma did not lower to VF64 fma")
    }

    let selectionSource = """
    kernel minimum(double a, double b) -> double {
        let condition = lt_quiet(a, b);
        return select(condition, a, b);
    }
    """
    let selectionA = (0..<lanes).map { Double($0 - 20) }
    let selectionB = (0..<lanes).map { Double(25 - $0) }
    let selectionInputs = bitsOf(selectionA) + bitsOf(selectionB)
    let selectionExpected = zip(selectionA, selectionB).map { min($0, $1).bitPattern }
    for mode in [VF64PrecisionMode.fast48, .wide48, .ieee64] {
        var selectionCompiler = VF64SourceCompiler(mode: mode, laneCount: lanes)
        let program = try selectionCompiler.compile(selectionSource)
        guard program.instructions.contains(where: { $0.opcode == .ltQuiet }),
              program.instructions.contains(where: { $0.opcode == .select }) else {
            throw HarnessError.validation("source comparison/select did not lower")
        }
        let result = try executeVF64(
            harness, program: program, inputs: selectionInputs
        )
        guard result.outputs == selectionExpected,
              result.flags.allSatisfy({ $0 == 0 }) else {
            throw HarnessError.validation(
                "source comparison/select execution mismatch for \(mode)"
            )
        }
    }

    do {
        var invalidCompiler = VF64SourceCompiler(mode: .ieee64, laneCount: 1)
        _ = try invalidCompiler.compile(
            "kernel bad(double x) -> double { return missing + x; }"
        )
        throw HarnessError.validation("invalid double source unexpectedly compiled")
    } catch is VF64CompilerError {
        // Expected diagnostic.
    }
    print("vf64-cc     arithmetic, comparison, and select lowered through all modes")
}
