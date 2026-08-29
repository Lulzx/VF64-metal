import Foundation

struct VF64ExponentInterval: Codable, Equatable {
    var minimum: Int
    var maximum: Int
    var finiteOnly: Bool
}

struct VF64InputProfile: Codable {
    let schemaVersion: Int
    let laneCount: Int
    let slots: [VF64ExponentInterval]
}

struct VF64SelectionDiagnostic: Codable {
    let instruction: Int
    let opcode: String
    let selectedMode: String
    let inferredExponent: VF64ExponentInterval?
    let requiredAccuracyBits: Int
    let estimatedAccuracyBits: Double
    let reason: String
}

struct VF64AutoDiagnostics: Codable {
    let schemaVersion: Int
    let requiredAccuracyBits: Int
    let laneCount: Int
    let selections: [VF64SelectionDiagnostic]
    let modeCounts: [String: Int]
}

private func exponentInterval(_ bits: UInt64) -> VF64ExponentInterval? {
    let magnitude = bits & 0x7fffffffffffffff
    let exponent = Int((magnitude >> 52) & 0x7ff)
    let fraction = magnitude & 0x000fffffffffffff
    if exponent == 0x7ff { return nil }
    if exponent == 0 && fraction == 0 {
        return VF64ExponentInterval(minimum: -1074, maximum: -1074, finiteOnly: true)
    }
    let unbiased: Int
    if exponent == 0 {
        unbiased = (63 - fraction.leadingZeroBitCount) - 1074
    } else {
        unbiased = exponent - 1023
    }
    return VF64ExponentInterval(
        minimum: unbiased, maximum: unbiased, finiteOnly: true
    )
}

func profileVF64Inputs(
    inputPath: String, outputPath: String, slots: Int, laneCount: Int
) throws {
    guard slots > 0, laneCount > 0 else {
        throw VF64CompilerError.invalid("profile slots and lanes must be positive")
    }
    let values = try decodeLittleEndian(
        Data(contentsOf: URL(fileURLWithPath: inputPath)), as: UInt64.self
    )
    guard values.count == slots * laneCount else {
        throw VF64CompilerError.invalid(
            "profile input has \(values.count) values; expected \(slots * laneCount)"
        )
    }
    var intervals: [VF64ExponentInterval] = []
    for slot in 0..<slots {
        let slice = values[(slot * laneCount)..<((slot + 1) * laneCount)]
        var minimum = Int.max
        var maximum = Int.min
        var finiteOnly = true
        for bits in slice {
            guard let interval = exponentInterval(bits) else {
                finiteOnly = false
                continue
            }
            minimum = min(minimum, interval.minimum)
            maximum = max(maximum, interval.maximum)
        }
        if minimum == Int.max { minimum = -1074; maximum = 1023 }
        intervals.append(VF64ExponentInterval(
            minimum: minimum, maximum: maximum, finiteOnly: finiteOnly
        ))
    }
    let profile = VF64InputProfile(
        schemaVersion: 1, laneCount: laneCount, slots: intervals
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(profile).write(
        to: URL(fileURLWithPath: outputPath), options: .atomic
    )
}

private func union(
    _ a: VF64ExponentInterval, _ b: VF64ExponentInterval,
    lowerGuardBits: Int = 0
) -> VF64ExponentInterval {
    VF64ExponentInterval(
        minimum: min(a.minimum, b.minimum) - lowerGuardBits,
        maximum: max(a.maximum, b.maximum) + 1,
        finiteOnly: a.finiteOnly && b.finiteOnly
    )
}

private func inferredArithmeticRange(
    opcode: VF64Opcode, sources: [VF64ExponentInterval]
) -> VF64ExponentInterval? {
    guard let a = sources.first else { return nil }
    switch opcode {
    case .add, .sub:
        guard sources.count == 2 else { return nil }
        return union(a, sources[1], lowerGuardBits: 48)
    case .mul:
        guard sources.count == 2 else { return nil }
        return VF64ExponentInterval(
            minimum: a.minimum + sources[1].minimum,
            maximum: a.maximum + sources[1].maximum + 1,
            finiteOnly: a.finiteOnly && sources[1].finiteOnly
        )
    case .div:
        guard sources.count == 2 else { return nil }
        return VF64ExponentInterval(
            minimum: a.minimum - sources[1].maximum - 1,
            maximum: a.maximum - sources[1].minimum + 1,
            finiteOnly: a.finiteOnly && sources[1].finiteOnly
        )
    case .sqrt:
        return VF64ExponentInterval(
            minimum: Int(floor(Double(a.minimum) / 2)) - 1,
            maximum: Int(ceil(Double(a.maximum) / 2)) + 1,
            finiteOnly: a.finiteOnly
        )
    case .fma:
        guard sources.count == 3,
              let product = inferredArithmeticRange(
                opcode: .mul, sources: Array(sources.prefix(2))
              ) else { return nil }
        return union(product, sources[2], lowerGuardBits: 48)
    default:
        return nil
    }
}

func selectVF64Precision(
    program: VF64Program, profile: VF64InputProfile,
    requiredAccuracyBits: Int
) throws -> (VF64Program, VF64AutoDiagnostics) {
    guard (1...53).contains(requiredAccuracyBits) else {
        throw VF64CompilerError.invalid("required accuracy must be 1...53 bits")
    }
    guard profile.schemaVersion == 1,
          profile.laneCount == program.laneCount,
          profile.slots.count == program.inputSlots else {
        throw VF64CompilerError.invalid("input profile does not match VF64 program")
    }
    var ranges: [UInt32: VF64ExponentInterval] = [:]
    var estimatedBits: [UInt32: Double] = [:]
    var reducedDepth: [UInt32: Int] = [:]
    var instructions = program.instructions
    var diagnostics: [VF64SelectionDiagnostic] = []
    var counts = ["fast48": 0, "wide48": 0, "ieee64": 0]
    let arithmetic: Set<VF64Opcode> = [.add, .sub, .mul, .div, .sqrt, .fma]

    for index in instructions.indices {
        var instruction = instructions[index]
        switch instruction.opcode {
        case .load:
            ranges[instruction.destination] = profile.slots[Int(instruction.immediate)]
            estimatedBits[instruction.destination] = 53
            reducedDepth[instruction.destination] = 0
        case .constant:
            ranges[instruction.destination] = exponentInterval(instruction.immediate)
            estimatedBits[instruction.destination] = 53
            reducedDepth[instruction.destination] = 0
        case .move:
            ranges[instruction.destination] = ranges[instruction.source0]
            estimatedBits[instruction.destination] = estimatedBits[instruction.source0]
            reducedDepth[instruction.destination] = reducedDepth[instruction.source0]
        case .select:
            if let a = ranges[instruction.source1], let b = ranges[instruction.source2] {
                ranges[instruction.destination] = union(a, b)
            }
            estimatedBits[instruction.destination] = min(
                estimatedBits[instruction.source1] ?? 0,
                estimatedBits[instruction.source2] ?? 0
            )
            reducedDepth[instruction.destination] = max(
                reducedDepth[instruction.source1] ?? 0,
                reducedDepth[instruction.source2] ?? 0
            )
        default:
            if arithmetic.contains(instruction.opcode) {
                let sourceRegisters = instruction.opcode == .sqrt
                    ? [instruction.source0]
                    : (instruction.opcode == .fma
                        ? [instruction.source0, instruction.source1, instruction.source2]
                        : [instruction.source0, instruction.source1])
                let sourceRanges = sourceRegisters.compactMap { ranges[$0] }
                let inferred = sourceRanges.count == sourceRegisters.count
                    ? inferredArithmeticRange(
                        opcode: instruction.opcode, sources: sourceRanges
                      ) : nil
                var mode: VF64PrecisionMode
                var reason: String
                let inputBits = sourceRegisters.compactMap { estimatedBits[$0] }.min() ?? 0
                let inputDepth = sourceRegisters.compactMap { reducedDepth[$0] }.max() ?? 0
                let candidateDepth = inputDepth + 1
                let reducedEstimate = min(inputBits, 48 - log2(Double(candidateDepth + 1)))
                if requiredAccuracyBits > 44 {
                    mode = .ieee64
                    reason = "accuracy contract exceeds reduced-mode 44-bit floor"
                } else if let inferred, inferred.finiteOnly,
                          inferred.minimum >= -100, inferred.maximum <= 120 {
                    mode = .fast48
                    reason = "finite inferred range fits fast48 headroom"
                } else if let inferred, inferred.finiteOnly {
                    mode = .wide48
                    reason = "finite inferred range requires scaled exponent"
                } else {
                    mode = .ieee64
                    reason = "range or finite-only proof is unavailable"
                }
                if mode != .ieee64 &&
                    reducedEstimate < Double(requiredAccuracyBits) {
                    mode = .ieee64
                    reason = "accumulated reduced-operation error budget is exhausted"
                }
                instruction.control = VF64Instruction.control(mode: mode)
                instructions[index] = instruction
                ranges[instruction.destination] = inferred
                let outputEstimate: Double
                if mode == .ieee64 {
                    outputEstimate = inputBits
                    reducedDepth[instruction.destination] = inputDepth
                } else {
                    outputEstimate = reducedEstimate
                    reducedDepth[instruction.destination] = candidateDepth
                }
                estimatedBits[instruction.destination] = outputEstimate
                let modeName = ["ieee64", "fast48", "wide48"][Int(mode.rawValue)]
                counts[modeName, default: 0] += 1
                diagnostics.append(VF64SelectionDiagnostic(
                    instruction: index,
                    opcode: String(describing: instruction.opcode),
                    selectedMode: modeName, inferredExponent: inferred,
                    requiredAccuracyBits: requiredAccuracyBits,
                    estimatedAccuracyBits: outputEstimate, reason: reason
                ))
            } else if instruction.opcode == .roundToInt {
                ranges[instruction.destination] = ranges[instruction.source0]
                estimatedBits[instruction.destination] = estimatedBits[instruction.source0]
                reducedDepth[instruction.destination] = reducedDepth[instruction.source0]
            } else {
                ranges[instruction.destination] = nil
                estimatedBits[instruction.destination] = nil
                reducedDepth[instruction.destination] = nil
            }
        }
    }
    let selected = VF64Program(
        registerCount: program.registerCount, inputSlots: program.inputSlots,
        outputSlots: program.outputSlots, laneCount: program.laneCount,
        instructions: instructions
    )
    try selected.validate()
    return (selected, VF64AutoDiagnostics(
        schemaVersion: 1, requiredAccuracyBits: requiredAccuracyBits,
        laneCount: program.laneCount, selections: diagnostics,
        modeCounts: counts
    ))
}

func compileVF64SourceFileAuto(
    sourcePath: String, outputPath: String, diagnosticsPath: String,
    profilePath: String, laneCount: Int, requiredAccuracyBits: Int
) throws {
    let source = try String(
        contentsOf: URL(fileURLWithPath: sourcePath), encoding: .utf8
    )
    var compiler = VF64SourceCompiler(mode: .ieee64, laneCount: laneCount)
    let base = try compiler.compile(source)
    let profile = try JSONDecoder().decode(
        VF64InputProfile.self,
        from: Data(contentsOf: URL(fileURLWithPath: profilePath))
    )
    let selected = try selectVF64Precision(
        program: base, profile: profile,
        requiredAccuracyBits: requiredAccuracyBits
    )
    try encodeLittleEndian(selected.0.words).write(
        to: URL(fileURLWithPath: outputPath), options: .atomic
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(selected.1).write(
        to: URL(fileURLWithPath: diagnosticsPath), options: .atomic
    )
}
