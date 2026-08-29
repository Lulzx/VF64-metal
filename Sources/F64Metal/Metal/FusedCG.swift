import Foundation
import Metal

extension MetalHarness {
    func fixedFast48CG(
        rowOffsets: [UInt32], columns: [UInt32], values: [Double], b: [Double],
        iterations: Int
    ) throws -> (x: [Double], residualSquared: Double, seconds: Double) {
        let count = b.count
        let rowBuffer = try buffer(rowOffsets)
        let columnBuffer = try buffer(columns)
        let valueBuffer = try buffer(bitsOf(values))
        let x = try buffer(bitsOf([Double](repeating: 0, count: count)))
        let r = try buffer(bitsOf(b))
        let p = try buffer(bitsOf(b))
        let ap = try emptyBuffer(count: count, of: UInt64.self)
        let rrA = try emptyBuffer(count: 1, of: UInt64.self)
        let rrB = try emptyBuffer(count: 1, of: UInt64.self)
        let pAp = try emptyBuffer(count: 1, of: UInt64.self)
        let alpha = try emptyBuffer(count: 1, of: UInt64.self)
        let beta = try emptyBuffer(count: 1, of: UInt64.self)
        let threads = 256
        let maximumPartials = max(1, (count + threads * 4 - 1) / (threads * 4))
        let partialA = try emptyBuffer(count: maximumPartials, of: SIMD2<Float>.self)
        let partialB = try emptyBuffer(count: maximumPartials, of: SIMD2<Float>.self)

        guard let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else {
            throw HarnessError.commandEncoding("could not encode fused CG")
        }
        func barrier() {
            encoder.memoryBarrier(scope: .buffers)
        }
        func dispatch(
            _ name: String, count dispatchCount: Int,
            buffers bindings: [(Int, MTLBuffer)], countIndex: Int?
        ) throws {
            let state = try pipeline(name)
            encoder.setComputePipelineState(state)
            for (index, value) in bindings {
                encoder.setBuffer(value, offset: 0, index: index)
            }
            if let countIndex {
                var n = UInt32(dispatchCount)
                encoder.setBytes(&n, length: 4, index: countIndex)
            }
            let width = min(
                state.maxTotalThreadsPerThreadgroup,
                max(1, state.threadExecutionWidth * 4)
            )
            encoder.dispatchThreads(
                MTLSize(width: dispatchCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
            )
        }
        func encodeDot(_ a: MTLBuffer, _ b: MTLBuffer, output: MTLBuffer) throws {
            var partialCount = max(1, (count + threads * 4 - 1) / (threads * 4))
            var input = partialA
            var next = partialB
            var state = try pipeline("dot_partial_kernel")
            encoder.setComputePipelineState(state)
            encoder.setBuffer(a, offset: 0, index: 0)
            encoder.setBuffer(b, offset: 0, index: 1)
            encoder.setBuffer(input, offset: 0, index: 2)
            var n = UInt32(count)
            encoder.setBytes(&n, length: 4, index: 3)
            encoder.setThreadgroupMemoryLength(
                threads * MemoryLayout<SIMD2<Float>>.stride, index: 0
            )
            encoder.dispatchThreadgroups(
                MTLSize(width: partialCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: threads, height: 1, depth: 1)
            )
            barrier()
            while partialCount > 1 {
                let nextCount = (partialCount + threads * 4 - 1) / (threads * 4)
                state = try pipeline("reduce_partial_kernel")
                encoder.setComputePipelineState(state)
                encoder.setBuffer(input, offset: 0, index: 0)
                encoder.setBuffer(next, offset: 0, index: 1)
                n = UInt32(partialCount)
                encoder.setBytes(&n, length: 4, index: 2)
                encoder.setThreadgroupMemoryLength(
                    threads * MemoryLayout<SIMD2<Float>>.stride, index: 0
                )
                encoder.dispatchThreadgroups(
                    MTLSize(width: nextCount, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: threads, height: 1, depth: 1)
                )
                barrier()
                swap(&input, &next)
                partialCount = nextCount
            }
            state = try pipeline("pack_partial_kernel")
            encoder.setComputePipelineState(state)
            encoder.setBuffer(input, offset: 0, index: 0)
            encoder.setBuffer(output, offset: 0, index: 1)
            encoder.dispatchThreads(
                MTLSize(width: 1, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
            )
            barrier()
        }

        var currentRR = rrA
        var nextRR = rrB
        try encodeDot(r, r, output: currentRR)
        for _ in 0..<iterations {
            try dispatch("spmv_fast48_kernel", count: count, buffers: [
                (0, rowBuffer), (1, columnBuffer), (2, valueBuffer),
                (3, p), (4, ap),
            ], countIndex: 5)
            barrier()
            try encodeDot(p, ap, output: pAp)
            try dispatch("scalar_div_fast48_kernel", count: 1, buffers: [
                (0, currentRR), (1, pAp), (2, alpha),
            ], countIndex: nil)
            barrier()
            try dispatch("cg_update_x_r_fast48_kernel", count: count, buffers: [
                (0, alpha), (1, p), (2, ap), (3, x), (4, r),
            ], countIndex: 5)
            barrier()
            try encodeDot(r, r, output: nextRR)
            try dispatch("scalar_div_fast48_kernel", count: 1, buffers: [
                (0, nextRR), (1, currentRR), (2, beta),
            ], countIndex: nil)
            barrier()
            try dispatch("cg_update_p_fast48_kernel", count: count, buffers: [
                (0, beta), (1, r), (2, p),
            ], countIndex: 3)
            barrier()
            swap(&currentRR, &nextRR)
        }
        encoder.endEncoding()
        let start = ContinuousClock.now
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error {
            throw HarnessError.commandEncoding(error.localizedDescription)
        }
        let wallSeconds = start.duration(to: .now).seconds
        let outputBits: [UInt64] = read(x, count: count)
        let rrBits: [UInt64] = read(currentRR, count: 1)
        return (
            outputBits.map(Double.init(bitPattern:)),
            Double(bitPattern: rrBits[0]), wallSeconds
        )
    }
}
