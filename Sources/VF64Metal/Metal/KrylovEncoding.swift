import Foundation
import Metal

/// Shared encoding for the fused fast48 Krylov solvers. Dot products use the
/// dot_partial_kernel lane layout: 256-thread groups, four elements per
/// thread, and reduce_partial_kernel levels until one group remains, so fused
/// and unfused reductions produce identical bits.
struct KrylovEncoding {
    static let threads = 256

    let harness: MetalHarness
    let submission: DeviceTerminatedSubmission
    let count: Int
    let partialA: MTLBuffer
    let partialB: MTLBuffer

    init(harness: MetalHarness, submission: DeviceTerminatedSubmission, count: Int) throws {
        self.harness = harness
        self.submission = submission
        self.count = count
        let partials = Self.groups(for: count)
        partialA = try harness.emptyBuffer(count: partials, of: SIMD2<Float>.self)
        partialB = try harness.emptyBuffer(count: partials, of: SIMD2<Float>.self)
    }

    static func groups(for elements: Int) -> Int {
        max(1, (elements + threads * 4 - 1) / (threads * 4))
    }

    var encoder: MTLComputeCommandEncoder { submission.encoder }

    func barrier() {
        encoder.memoryBarrier(scope: .buffers)
    }

    func bind(_ bindings: [(Int, MTLBuffer, Int)], words: [(Int, UInt32)] = [],
              floats: [(Int, Float)] = []) {
        for (index, buffer, offset) in bindings {
            encoder.setBuffer(buffer, offset: offset, index: index)
        }
        for (index, word) in words {
            var value = word
            encoder.setBytes(&value, length: 4, index: index)
        }
        for (index, float) in floats {
            var value = float
            encoder.setBytes(&value, length: 4, index: index)
        }
    }

    /// Elementwise dispatch over `elements` threads.
    func dispatch(
        _ name: String, elements: Int, _ bindings: [(Int, MTLBuffer, Int)],
        words: [(Int, UInt32)] = []
    ) throws {
        let state = try harness.pipeline(name)
        encoder.setComputePipelineState(state)
        bind(bindings, words: words)
        let width = min(
            state.maxTotalThreadsPerThreadgroup,
            max(1, state.threadExecutionWidth * 4)
        )
        encoder.dispatchThreads(
            MTLSize(width: elements, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
        barrier()
    }

    /// Dispatch in the dot-partial layout; the kernel writes `partialA`.
    func dispatchPartial(
        _ name: String, _ bindings: [(Int, MTLBuffer, Int)],
        words: [(Int, UInt32)] = []
    ) throws {
        let state = try harness.pipeline(name)
        encoder.setComputePipelineState(state)
        bind(bindings, words: words)
        encoder.setThreadgroupMemoryLength(
            Self.threads * MemoryLayout<SIMD2<Float>>.stride, index: 0
        )
        encoder.dispatchThreadgroups(
            MTLSize(width: Self.groups(for: count), height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: Self.threads, height: 1, depth: 1)
        )
        barrier()
    }

    /// Reduces `partialA` until one group remains and returns the buffer and
    /// partial count the final single-group stage consumes.
    func reduceToFinalGroup() throws -> (MTLBuffer, UInt32) {
        var partialCount = Self.groups(for: count)
        var input = partialA
        var next = partialB
        while partialCount > Self.threads * 4 {
            let nextCount = Self.groups(for: partialCount)
            try dispatchGroups("reduce_partial_kernel", groups: nextCount, [
                (0, input, 0), (1, next, 0),
            ], words: [(2, UInt32(partialCount))])
            swap(&input, &next)
            partialCount = nextCount
        }
        return (input, UInt32(partialCount))
    }

    func dispatchGroups(
        _ name: String, groups: Int, _ bindings: [(Int, MTLBuffer, Int)],
        words: [(Int, UInt32)] = [], floats: [(Int, Float)] = []
    ) throws {
        let state = try harness.pipeline(name)
        encoder.setComputePipelineState(state)
        bind(bindings, words: words, floats: floats)
        encoder.setThreadgroupMemoryLength(
            Self.threads * MemoryLayout<SIMD2<Float>>.stride, index: 0
        )
        encoder.dispatchThreadgroups(
            MTLSize(width: groups, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: Self.threads, height: 1, depth: 1)
        )
        barrier()
    }

    /// Partials of dot(a, b) over shadows, written to `partialA`.
    func dotPartial(_ a: MTLBuffer, _ b: MTLBuffer, aOffset: Int = 0) throws {
        try dispatchPartial("krylov_dot_partial_fast48_kernel", [
            (0, a, aOffset), (1, b, 0), (2, partialA, 0),
        ], words: [(3, UInt32(count))])
    }

    /// dot(a, b) over shadows, packed into `output` at `offset`.
    func dot(
        _ a: MTLBuffer, _ b: MTLBuffer, aOffset: Int = 0,
        into output: MTLBuffer, offset: Int = 0
    ) throws {
        try dotPartial(a, b, aOffset: aOffset)
        try packFinal(into: output, offset: offset)
    }

    /// Decodes binary64 storage into a pair shadow.
    func decode(_ input: MTLBuffer, into output: MTLBuffer, elements: Int) throws {
        try dispatch("krylov_decode_fast48_kernel", elements: elements, [
            (0, input, 0), (1, output, 0),
        ], words: [(2, UInt32(elements))])
    }

    func packFinal(into output: MTLBuffer, offset: Int = 0) throws {
        let (partials, partialCount) = try reduceToFinalGroup()
        try dispatchGroups("krylov_dot_pack_fast48_kernel", groups: 1, [
            (0, partials, 0), (1, output, offset),
        ], words: [(2, partialCount)])
    }
}
