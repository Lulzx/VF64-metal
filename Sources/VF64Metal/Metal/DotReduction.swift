import Foundation
import Metal

extension MetalHarness {
    func dot(
        a: MTLBuffer,
        b: MTLBuffer,
        count: Int,
        firstKernel: String = "dot_partial_kernel"
    ) throws -> (Double, Double) {
        let threads = 256
        var partialCount = (count + threads * 4 - 1) / (threads * 4)
        var firstOutput = try emptyBuffer(
            count: max(1, partialCount), of: SIMD2<Float>.self
        )
        let start = ContinuousClock.now

        do {
            let pipeline = try pipeline(firstKernel)
            guard let command = queue.makeCommandBuffer(),
                  let encoder = command.makeComputeCommandEncoder() else {
                throw HarnessError.commandEncoding("could not encode dot partials")
            }
            command.label = "vf64:\(firstKernel)"
            encoder.label = "vf64:\(firstKernel)"
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(a, offset: 0, index: 0)
            encoder.setBuffer(b, offset: 0, index: 1)
            encoder.setBuffer(firstOutput, offset: 0, index: 2)
            var n = UInt32(count)
            encoder.setBytes(&n, length: 4, index: 3)
            encoder.setThreadgroupMemoryLength(
                threads * MemoryLayout<SIMD2<Float>>.stride, index: 0
            )
            encoder.dispatchThreadgroups(
                MTLSize(width: partialCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: threads, height: 1, depth: 1)
            )
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            if let error = command.error {
                throw HarnessError.commandEncoding(error.localizedDescription)
            }
        }

        while partialCount > 1 {
            let nextCount = (partialCount + threads * 4 - 1) / (threads * 4)
            let nextOutput = try emptyBuffer(count: nextCount, of: SIMD2<Float>.self)
            let pipeline = try pipeline("reduce_partial_kernel")
            guard let command = queue.makeCommandBuffer(),
                  let encoder = command.makeComputeCommandEncoder() else {
                throw HarnessError.commandEncoding("could not encode dot reduction")
            }
            command.label = "vf64:reduce_partial_kernel"
            encoder.label = "vf64:reduce_partial_kernel"
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(firstOutput, offset: 0, index: 0)
            encoder.setBuffer(nextOutput, offset: 0, index: 1)
            var n = UInt32(partialCount)
            encoder.setBytes(&n, length: 4, index: 2)
            encoder.setThreadgroupMemoryLength(
                threads * MemoryLayout<SIMD2<Float>>.stride, index: 0
            )
            encoder.dispatchThreadgroups(
                MTLSize(width: nextCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: threads, height: 1, depth: 1)
            )
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            if let error = command.error {
                throw HarnessError.commandEncoding(error.localizedDescription)
            }
            firstOutput = nextOutput
            partialCount = nextCount
        }

        let packed = try emptyBuffer(count: 1, of: UInt64.self)
        let pipeline = try pipeline("pack_partial_kernel")
        guard let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else {
            throw HarnessError.commandEncoding("could not encode dot pack")
        }
        command.label = "vf64:pack_partial_kernel"
        encoder.label = "vf64:pack_partial_kernel"
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(firstOutput, offset: 0, index: 0)
        encoder.setBuffer(packed, offset: 0, index: 1)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error {
            throw HarnessError.commandEncoding(error.localizedDescription)
        }
        let bits: UInt64 = read(packed, count: 1)[0]
        return (Double(bitPattern: bits), start.duration(to: .now).seconds)
    }
}
