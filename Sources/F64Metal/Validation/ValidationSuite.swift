import Foundation

func runValidation(_ harness: MetalHarness) throws {
    print("Device: \(harness.device.name)")
    try validateCodec(harness)
    try validateSpecialValues(harness)
    try validateExactHostOracle(harness)
    try validateWideMode(harness)
    try validateVirtualISA(harness)
    try validateVF64SourceCompiler(harness)

    var rng = SplitMix64(state: 0xdecafbad12345678)
    let count = 32_768
    // Leave at least 24 exponent bits of headroom for the residual limb after
    // multiplication. Near FP32 underflow, ~24-bit results are contractual.
    let a = (0..<count).map { _ in rng.finiteValue(exponentRange: -40...40) }
    let b = (0..<count).map { _ in rng.finiteValue(exponentRange: -40...40) }
    let c = (0..<count).map { _ in rng.finiteValue(exponentRange: -40...40) }
    try validateOperation(
        harness, kernel: "add_kernel", label: "add", a: a, b: b,
        reference: { $0 + $1 + $2 }
    )
    try validateOperation(
        harness, kernel: "mul_kernel", label: "multiply", a: a, b: b,
        reference: { $0 * $1 + $2 }
    )
    try validateOperation(
        harness, kernel: "mul_short_kernel", label: "mul-short", a: a, b: b,
        reference: { $0 * $1 + $2 }
    )
    try validateOperation(
        harness, kernel: "mul_dekker_kernel", label: "mul-dekker", a: a, b: b,
        reference: { $0 * $1 + $2 }
    )
    let divisors = b.map { abs($0) < 0x1p-50 ? 1.0 : $0 }
    try validateOperation(
        harness, kernel: "div_kernel", label: "divide", a: a, b: divisors,
        reference: { $0 / $1 + $2 }, minimumP01: 40
    )
    try validateOperation(
        harness, kernel: "div_one_kernel", label: "div-1corr", a: a, b: divisors,
        reference: { $0 / $1 + $2 }, minimumP01: 40
    )
    try validateOperation(
        harness, kernel: "fma_kernel", label: "fma", a: a, b: b, c: c,
        reference: { $2.addingProduct($0, $1) }
    )
    try validateDot(
        harness, a: Array(a.prefix(16_384)), b: Array(b.prefix(16_384))
    )
    print("Validation passed")
}
