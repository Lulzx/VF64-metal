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

    struct ConversionCase {
        let parameterType: String
        let returnType: String
        let function: String
        let opcode: VF64Opcode
        let inputs: [UInt64]
        let expected: [UInt64]
    }
    let u32 = (0..<lanes).map { UInt32($0 * 65_537) }
    let u64 = (0..<lanes).map { UInt64(9_007_199_254_740_992) + UInt64($0 * 3) }
    let i32 = (0..<lanes).map { Int32($0 - 32) * 1_000_003 }
    let i64 = (0..<lanes).map { Int64($0 - 32) * 9_007_199_254_741 }
    let exactDoubles = (0..<lanes).map { Double($0 - 32) }
    let positiveDoubles = (0..<lanes).map { Double($0 * 17) }
    let floatValues = (0..<lanes).map { Float($0 - 32) * 0.25 }
    let halfValues = (0..<lanes).map { Float16($0 - 32) * Float16(0.25) }
    let conversionCases = [
        ConversionCase(
            parameterType: "uint32", returnType: "double",
            function: "uint32_to_double", opcode: .ui32ToF64,
            inputs: u32.map(UInt64.init),
            expected: u32.map { Double($0).bitPattern }
        ),
        ConversionCase(
            parameterType: "uint64", returnType: "double",
            function: "uint64_to_double", opcode: .ui64ToF64,
            inputs: u64, expected: u64.map { Double($0).bitPattern }
        ),
        ConversionCase(
            parameterType: "int32", returnType: "double",
            function: "int32_to_double", opcode: .i32ToF64,
            inputs: i32.map { UInt64(UInt32(bitPattern: $0)) },
            expected: i32.map { Double($0).bitPattern }
        ),
        ConversionCase(
            parameterType: "int64", returnType: "double",
            function: "int64_to_double", opcode: .i64ToF64,
            inputs: i64.map { UInt64(bitPattern: $0) },
            expected: i64.map { Double($0).bitPattern }
        ),
        ConversionCase(
            parameterType: "double", returnType: "uint32",
            function: "double_to_uint32", opcode: .f64ToUi32,
            inputs: positiveDoubles.map(\.bitPattern),
            expected: positiveDoubles.map { UInt64(UInt32($0)) }
        ),
        ConversionCase(
            parameterType: "double", returnType: "uint64",
            function: "double_to_uint64", opcode: .f64ToUi64,
            inputs: positiveDoubles.map(\.bitPattern),
            expected: positiveDoubles.map { UInt64($0) }
        ),
        ConversionCase(
            parameterType: "double", returnType: "int32",
            function: "double_to_int32", opcode: .f64ToI32,
            inputs: exactDoubles.map(\.bitPattern),
            expected: exactDoubles.map {
                UInt64(UInt32(bitPattern: Int32($0)))
            }
        ),
        ConversionCase(
            parameterType: "double", returnType: "int64",
            function: "double_to_int64", opcode: .f64ToI64,
            inputs: exactDoubles.map(\.bitPattern),
            expected: exactDoubles.map { UInt64(bitPattern: Int64($0)) }
        ),
        ConversionCase(
            parameterType: "double", returnType: "float",
            function: "double_to_float", opcode: .f64ToF32,
            inputs: exactDoubles.map(\.bitPattern),
            expected: exactDoubles.map { UInt64(Float($0).bitPattern) }
        ),
        ConversionCase(
            parameterType: "double", returnType: "half",
            function: "double_to_half", opcode: .f64ToF16,
            inputs: exactDoubles.map(\.bitPattern),
            expected: exactDoubles.map { UInt64(Float16($0).bitPattern) }
        ),
        ConversionCase(
            parameterType: "float", returnType: "double",
            function: "float_to_double", opcode: .f32ToF64,
            inputs: floatValues.map { UInt64($0.bitPattern) },
            expected: floatValues.map { Double($0).bitPattern }
        ),
        ConversionCase(
            parameterType: "half", returnType: "double",
            function: "half_to_double", opcode: .f16ToF64,
            inputs: halfValues.map { UInt64($0.bitPattern) },
            expected: halfValues.map { Double($0).bitPattern }
        ),
    ]
    for item in conversionCases {
        let source = """
        kernel convert(\(item.parameterType) value) -> \(item.returnType) {
            return \(item.function)(value);
        }
        """
        var compiler = VF64SourceCompiler(mode: .ieee64, laneCount: lanes)
        let program = try compiler.compile(source)
        guard program.instructions.contains(where: { $0.opcode == item.opcode }) else {
            throw HarnessError.validation(
                "source conversion \(item.function) did not lower"
            )
        }
        let result = try executeVF64(
            harness, program: program, inputs: item.inputs
        )
        let expectedFlags: [UInt32]
        if item.opcode == .ui64ToF64 {
            expectedFlags = zip(item.inputs, item.expected).map {
                UInt64(Double(bitPattern: $0.1)) == $0.0 ? 0 : 1
            }
        } else if item.opcode == .i64ToF64 {
            expectedFlags = zip(item.inputs, item.expected).map {
                Int64(Double(bitPattern: $0.1)) == Int64(bitPattern: $0.0) ? 0 : 1
            }
        } else {
            expectedFlags = [UInt32](repeating: 0, count: lanes)
        }
        guard result.outputs == item.expected,
              result.flags == expectedFlags else {
            let mismatch = zip(result.outputs, item.expected).enumerated().first {
                $0.element.0 != $0.element.1
            }
            let detail: String
            if let mismatch {
                detail = " at lane \(mismatch.offset): got 0x\(String(mismatch.element.0, radix: 16)), expected 0x\(String(mismatch.element.1, radix: 16)), input 0x\(String(item.inputs[mismatch.offset], radix: 16))"
            } else {
                let flagMismatch = zip(result.flags, expectedFlags).enumerated().first {
                    $0.element.0 != $0.element.1
                }
                detail = flagMismatch.map {
                    " at lane \($0.offset): flags \($0.element.0), expected \($0.element.1)"
                } ?? " (flags)"
            }
            throw HarnessError.validation(
                "source conversion \(item.function) execution mismatch\(detail)"
            )
        }
    }

    for invalidSource in [
        "kernel bad(int64 x) -> int64 { return x + x; }",
        "kernel bad(double x) -> int64 { return x; }",
        "kernel bad(bool c, double x, int64 y) -> double { return select(c, x, y); }",
    ] {
        do {
            var invalidCompiler = VF64SourceCompiler(mode: .ieee64, laneCount: 1)
            _ = try invalidCompiler.compile(invalidSource)
            throw HarnessError.validation(
                "invalid typed source unexpectedly compiled"
            )
        } catch is VF64CompilerError {
            // Expected diagnostic.
        }
    }

    var chainLines = [
        "kernel long_chain(double x, double factor) -> double {",
        "    let v0: double = x * factor;",
    ]
    for index in 1..<96 {
        chainLines.append(
            "    let v\(index): double = v\(index - 1) * factor;"
        )
    }
    chainLines.append("    return v95;")
    chainLines.append("}")
    var chainCompiler = VF64SourceCompiler(mode: .ieee64, laneCount: lanes)
    let chainProgram = try chainCompiler.compile(
        chainLines.joined(separator: "\n")
    )
    guard chainProgram.registerCount == 2,
          chainProgram.instructions.filter({ $0.opcode == .mul }).count == 96 else {
        throw HarnessError.validation(
            "long source chain was not allocated to two live VF64 registers"
        )
    }
    let chainX = (0..<lanes).map { 0.75 + Double($0) * 0.001 }
    let chainFactor = Array(repeating: 1.0001, count: lanes)
    let chainExpected = zip(chainX, chainFactor).map { pair -> UInt64 in
        var value = pair.0
        for _ in 0..<96 { value *= pair.1 }
        return value.bitPattern
    }
    let chainResult = try executeVF64(
        harness, program: chainProgram,
        inputs: bitsOf(chainX) + bitsOf(chainFactor)
    )
    guard chainResult.outputs == chainExpected,
          chainResult.flags.allSatisfy({ $0 == 1 }) else {
        throw HarnessError.validation("long allocated source chain mismatch")
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
    print("vf64-cc     typed ops, 12 conversions, and 96-op chain in 2 registers passed")
}
