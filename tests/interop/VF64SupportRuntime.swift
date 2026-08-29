import Foundation
import Metal

guard CommandLine.arguments.count == 2 else {
    fatalError("usage: VF64SupportRuntime.swift PROBE.metallib")
}
guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("no Metal device")
}
let library = try device.makeLibrary(
    URL: URL(fileURLWithPath: CommandLine.arguments[1])
)
guard let function = library.makeFunction(name: "vf64_support_probe") else {
    fatalError("missing vf64_support_probe")
}
let pipeline = try device.makeComputePipelineState(function: function)
guard let output = device.makeBuffer(length: 9 * MemoryLayout<UInt64>.stride),
      let queue = device.makeCommandQueue(),
      let command = queue.makeCommandBuffer(),
      let encoder = command.makeComputeCommandEncoder() else {
    fatalError("Metal allocation failed")
}
encoder.setComputePipelineState(pipeline)
encoder.setBuffer(output, offset: 0, index: 0)
encoder.dispatchThreads(
    MTLSize(width: 1, height: 1, depth: 1),
    threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
)
encoder.endEncoding()
command.commit()
command.waitUntilCompleted()
if let error = command.error { throw error }

let observed = Array(UnsafeBufferPointer(
    start: output.contents().bindMemory(to: UInt64.self, capacity: 9),
    count: 9
))
let onePlusULP = Double(bitPattern: 0x3ff0000000000001)
let expected: [UInt64] = [
    (1.0 + Double(bitPattern: 0x3ca0000000000000)).bitPattern,
    (onePlusULP * 3.0).bitPattern,
    (1.0 / 3.0).bitPattern,
    2.0.squareRoot().bitPattern,
    Double(bitPattern: 0xbff0000000000002).addingProduct(
        onePlusULP, onePlusULP
    ).bitPattern,
    1,
    Double(UInt64.max).bitPattern,
]
guard Array(observed.prefix(7)) == expected else {
    fatalError(
        "VF64 support mismatch got=\(observed.map { String($0, radix: 16) }) " +
        "expected=\(expected.map { String($0, radix: 16) })"
    )
}
let wideReferences = [1.0e300 + 1.0e300, 1.0e200 * 1.0e100]
for (bits, reference) in zip(observed.suffix(2), wideReferences) {
    let value = Double(bitPattern: bits)
    let relativeError = abs(value - reference) / abs(reference)
    guard value.isFinite && relativeError <= Double(sign: .plus, exponent: -45, significand: 1) else {
        fatalError("wide48 support error \(relativeError) exceeds 2^-45")
    }
}
print("vf64_support_runtime=pass exact_cases=7 wide48_cases=2")
