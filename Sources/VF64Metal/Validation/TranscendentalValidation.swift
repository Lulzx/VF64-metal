import Foundation

// M9 differential conformance against the pinned MPFR oracle.
//
// Berkeley TestFloat has no transcendental generators, so this path consumes
// vectors from tools/m9/m9_ref.c instead. The line format is deliberately the
// same as the TestFloat vectors the runner already accepts:
//
//     <argument bits> <result bits> <exception flags>
//     <first bits> <second bits> <result bits> <exception flags>   (hypot, atan2, pow)
//
// Two things are checked per case: the delivered bits and flags against the
// oracle, and the per-call certification the kernel reports. An uncertified
// case is not a wrong answer; it is a case where the evaluation error is not
// provably smaller than the distance to the rounding boundary, so correct
// rounding cannot be claimed for it. Both counts are reported and both must be
// zero for the run to pass.

private struct TranscendentalCase {
    let argument: UInt64
    let second: UInt64
    let expected: UInt64
    let expectedFlags: UInt8
}

let transcendentalRoundingModes: [String: UInt32] = [
    "rnear_even": 0,
    "rminMag": 1,
    "rmin": 2,
    "rmax": 3,
    "rnear_maxMag": 4,
]

private let transcendentalKernels: [String: String] = [
    "f64_exp": "soft_exp_round_kernel",
    "f64_exp2": "soft_exp2_64_round_kernel",
    "f64_expm1": "soft_expm1_64_round_kernel",
    "f64_log": "soft_log64_round_kernel",
    "f64_log2": "soft_log2_64_round_kernel",
    "f64_log1p": "soft_log1p64_round_kernel",
    "f64_cbrt": "soft_cbrt64_round_kernel",
    "f64_hypot": "soft_hypot64_round_kernel",
    "f64_atan": "soft_atan64_round_kernel",
    "f64_asin": "soft_asin64_round_kernel",
    "f64_acos": "soft_acos64_round_kernel",
    "f64_atan2": "soft_atan2_64_round_kernel",
    "f64_pow": "soft_pow64_round_kernel",
]

private let binaryTranscendentals: Set<String> = ["f64_hypot", "f64_atan2", "f64_pow"]

func runTranscendentalConformance(
    _ harness: MetalHarness,
    function: String,
    rounding: String,
    batchSize: Int = 65_536,
    inputLine: () -> String? = { readLine() }
) throws {
    guard let kernel = transcendentalKernels[function] else {
        throw HarnessError.validation(
            "transcendental function \(function) is not implemented; supported: " +
            transcendentalKernels.keys.sorted().joined(separator: ", ")
        )
    }
    guard let roundingMode = transcendentalRoundingModes[rounding] else {
        throw HarnessError.validation(
            "unknown rounding mode \(rounding); supported: " +
            transcendentalRoundingModes.keys.sorted().joined(separator: ", ")
        )
    }
    let roundingBuffer = try harness.buffer([roundingMode])
    let binary = binaryTranscendentals.contains(function)

    var batch: [TranscendentalCase] = []
    batch.reserveCapacity(batchSize)
    var total = 0
    var malformed = 0
    var uncertified = 0
    var mismatches: [String] = []
    var flagged = 0

    func validateBatch(_ cases: [TranscendentalCase]) throws {
        guard !cases.isEmpty else { return }
        let argumentBuffer = try harness.buffer(cases.map(\.argument))
        let secondBuffer = try harness.buffer(cases.map(\.second))
        let output = try harness.emptyBuffer(count: cases.count, of: UInt64.self)
        let flags = try harness.emptyBuffer(count: cases.count, of: UInt32.self)
        let certified = try harness.emptyBuffer(count: cases.count, of: UInt32.self)
        _ = try harness.run(
            kernel, count: cases.count,
            buffers: [
                (0, argumentBuffer), (1, secondBuffer), (2, output),
                (4, roundingBuffer), (6, flags), (7, certified),
            ],
            countIndex: 3
        )
        let observed: [UInt64] = harness.read(output, count: cases.count)
        let observedFlags: [UInt32] = harness.read(flags, count: cases.count)
        let observedCertification: [UInt32] = harness.read(
            certified, count: cases.count
        )
        for index in cases.indices {
            if observedCertification[index] == 0 { uncertified += 1 }
            guard observed[index] != cases[index].expected ||
                    observedFlags[index] != UInt32(cases[index].expectedFlags) ||
                    observedCertification[index] == 0 else { continue }
            if mismatches.count < 20 {
                mismatches.append(String(
                    format: "case %d: a=%016llx b=%016llx got=%016llx " +
                            "want=%016llx flags=%02x wantFlags=%02x certified=%u",
                    total + index,
                    cases[index].argument,
                    cases[index].second,
                    observed[index],
                    cases[index].expected,
                    observedFlags[index],
                    cases[index].expectedFlags,
                    observedCertification[index]
                ))
            }
        }
    }

    while let line = inputLine() {
        let fields = line.split(whereSeparator: \.isWhitespace)
        let operands = binary ? 2 : 1
        guard fields.count == operands + 2,
              let argument = UInt64(fields[0], radix: 16),
              let second = binary ? UInt64(fields[1], radix: 16) : 0,
              let expected = UInt64(fields[operands], radix: 16),
              let flags = UInt8(fields[operands + 1], radix: 16) else {
            malformed += 1
            continue
        }
        batch.append(TranscendentalCase(
            argument: argument, second: second, expected: expected,
            expectedFlags: flags
        ))
        if flags != 0 { flagged += 1 }
        if batch.count == batchSize {
            try validateBatch(batch)
            total += batch.count
            batch.removeAll(keepingCapacity: true)
        }
    }
    try validateBatch(batch)
    total += batch.count

    let mismatchCount = mismatches.count
    print(
        "{\"function\":\"\(function)\",\"rounding\":\"\(rounding)\"," +
        "\"cases\":\(total),\"mismatches\":\(mismatchCount)," +
        "\"uncertified\":\(uncertified),\"oracle_flagged\":\(flagged)," +
        "\"malformed\":\(malformed)}"
    )

    guard malformed == 0 else {
        throw HarnessError.validation(
            "MPFR input contained \(malformed) malformed lines"
        )
    }
    guard total > 0 else {
        throw HarnessError.validation("MPFR input contained no cases")
    }
    guard mismatches.isEmpty else {
        throw HarnessError.validation(
            "\(function) MPFR result mismatches:\n" +
            mismatches.joined(separator: "\n")
        )
    }
    print(
        "\(function) \(rounding) MPFR conformance passed over \(total) cases; " +
        "result bits and exception flags compared exactly; " +
        "every result certified correctly rounded " +
        "(\(flagged) oracle cases raised flags)"
    )
}

// Built-in smoke coverage so that `validate` exercises every M9 function
// without the external oracle. These vectors were produced by the same pinned
// MPFR generator; they are a self-check, not the M9 gate, which remains
// scripts/run-mpfr-m9.sh.
func validateTranscendental(_ harness: MetalHarness) throws {
    for (function, modes) in m9SmokeVectors.sorted(by: { $0.key < $1.key }) {
        let kernel = transcendentalKernels[function]!
        var total = 0
        for (rounding, vectors) in modes.sorted(by: { $0.key < $1.key }) {
            let roundingBuffer = try harness.buffer([transcendentalRoundingModes[rounding]!])
            let first = try harness.buffer(vectors.map(\.0))
            let second = try harness.buffer(vectors.map(\.1))
            let output = try harness.emptyBuffer(count: vectors.count, of: UInt64.self)
            let flags = try harness.emptyBuffer(count: vectors.count, of: UInt32.self)
            let certified = try harness.emptyBuffer(count: vectors.count, of: UInt32.self)
            _ = try harness.run(
                kernel, count: vectors.count,
                buffers: [
                    (0, first), (1, second), (2, output), (4, roundingBuffer),
                    (6, flags), (7, certified),
                ],
                countIndex: 3
            )
            let observed: [UInt64] = harness.read(output, count: vectors.count)
            let observedFlags: [UInt32] = harness.read(flags, count: vectors.count)
            let observedCertification: [UInt32] = harness.read(
                certified, count: vectors.count
            )
            for index in vectors.indices {
                let (a, b, expected, expectedFlags) = vectors[index]
                guard observed[index] == expected,
                      observedFlags[index] == UInt32(expectedFlags),
                      observedCertification[index] == 1 else {
                    throw HarnessError.validation(String(
                        format: "%@ %@ mismatch: a=%016llx b=%016llx got=%016llx " +
                                "want=%016llx flags=%02x wantFlags=%02x certified=%u",
                        function, rounding, a, b, observed[index], expected,
                        observedFlags[index], expectedFlags,
                        observedCertification[index]
                    ))
                }
            }
            total += vectors.count
        }
        let name = String(function.dropFirst(4))
        print(
            "\(name.padding(toLength: 12, withPad: " ", startingAt: 0))" +
            "\(total) pinned MPFR vectors across five rounding modes " +
            "passed with bitwise results, flags, and certification"
        )
    }
}
