import Foundation
import Metal

extension MetalHarness {
    func deviceConvergedFast48GMRES(
        rowOffsets: [UInt32], columns: [UInt32], values: [Double], b: [Double],
        tolerance: Double, maxIterations: Int
    ) throws -> (x: [Double], iterations: Int, residualEstimate: Double, seconds: Double) {
        let count = b.count
        let stride = maxIterations
        let rowBuffer = try buffer(rowOffsets)
        let columnBuffer = try buffer(columns)
        let valueBuffer = try buffer(bitsOf(values))
        let bBuffer = try buffer(bitsOf(b))
        let x = try buffer(bitsOf([Double](repeating: 0, count: count)))
        let work = try emptyBuffer(count: count, of: UInt64.self)
        let basis = try (0...maxIterations).map { _ in
            try emptyBuffer(count: count, of: UInt64.self)
        }
        let h = try buffer([UInt64](repeating: 0, count: (maxIterations + 1) * stride))
        let cosine = try buffer([UInt64](repeating: 0, count: maxIterations))
        let sine = try buffer([UInt64](repeating: 0, count: maxIterations))
        let g = try buffer([UInt64](repeating: 0, count: maxIterations + 1))
        let y = try buffer([UInt64](repeating: 0, count: maxIterations))
        let normSquared = try emptyBuffer(count: 1, of: UInt64.self)
        let inverseNorm = try emptyBuffer(count: 1, of: UInt64.self)
        let initialNorm = try emptyBuffer(count: 1, of: UInt64.self)
        let completed = try buffer([UInt32(0)])
        let convergedResidual = try emptyBuffer(count: 1, of: UInt64.self)
        let threads = 256
        let maximumPartials = max(1, (count + threads * 4 - 1) / (threads * 4))
        let partialA = try emptyBuffer(count: maximumPartials, of: SIMD2<Float>.self)
        let partialB = try emptyBuffer(count: maximumPartials, of: SIMD2<Float>.self)

        guard let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else {
            throw HarnessError.commandEncoding("could not encode fused GMRES")
        }
        command.label = "vf64:fused_gmres"
        encoder.label = "vf64:fused_gmres"

        func barrier() {
            encoder.memoryBarrier(scope: .buffers)
        }
        func dispatch(
            _ name: String, count dispatchCount: Int,
            buffers bindings: [(index: Int, buffer: MTLBuffer, offset: Int)],
            countIndex: Int?
        ) throws {
            let state = try pipeline(name)
            encoder.setComputePipelineState(state)
            for binding in bindings {
                encoder.setBuffer(
                    binding.buffer, offset: binding.offset, index: binding.index
                )
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
        func encodeDot(
            _ a: MTLBuffer, _ b: MTLBuffer, output: MTLBuffer,
            outputOffset: Int = 0
        ) throws {
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
            encoder.setBuffer(output, offset: outputOffset, index: 1)
            encoder.dispatchThreads(
                MTLSize(width: 1, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
            )
            barrier()
        }

        try encodeDot(bBuffer, bBuffer, output: normSquared)
        try dispatch("gmres_initialize_fast48_kernel", count: 1, buffers: [
            (0, normSquared, 0), (1, inverseNorm, 0), (2, g, 0),
            (3, initialNorm, 0),
        ], countIndex: nil)
        barrier()
        try dispatch("vector_scale_fast48_kernel", count: count, buffers: [
            (0, inverseNorm, 0), (1, bBuffer, 0), (2, basis[0], 0),
        ], countIndex: 3)
        barrier()

        for column in 0..<maxIterations {
            try dispatch("spmv_fast48_kernel", count: count, buffers: [
                (0, rowBuffer, 0), (1, columnBuffer, 0), (2, valueBuffer, 0),
                (3, basis[column], 0), (4, work, 0),
            ], countIndex: 5)
            barrier()
            for row in 0...column {
                let coefficientOffset = (row * stride + column) * MemoryLayout<UInt64>.stride
                try encodeDot(
                    basis[row], work, output: h, outputOffset: coefficientOffset
                )
                try dispatch("gmres_orthogonalize_fast48_kernel", count: count, buffers: [
                    (0, h, coefficientOffset), (1, basis[row], 0), (2, work, 0),
                ], countIndex: 3)
                barrier()
            }
            try encodeDot(work, work, output: normSquared)
            var columnValue = UInt32(column)
            var strideValue = UInt32(stride)
            var toleranceValue = Float(tolerance)
            let finalize = try pipeline("gmres_finalize_column_fast48_kernel")
            encoder.setComputePipelineState(finalize)
            encoder.setBuffer(h, offset: 0, index: 0)
            encoder.setBuffer(normSquared, offset: 0, index: 1)
            encoder.setBuffer(cosine, offset: 0, index: 2)
            encoder.setBuffer(sine, offset: 0, index: 3)
            encoder.setBuffer(g, offset: 0, index: 4)
            encoder.setBuffer(inverseNorm, offset: 0, index: 5)
            encoder.setBuffer(initialNorm, offset: 0, index: 6)
            encoder.setBuffer(completed, offset: 0, index: 7)
            encoder.setBuffer(convergedResidual, offset: 0, index: 8)
            encoder.setBytes(&columnValue, length: 4, index: 9)
            encoder.setBytes(&strideValue, length: 4, index: 10)
            encoder.setBytes(&toleranceValue, length: 4, index: 11)
            encoder.dispatchThreads(
                MTLSize(width: 1, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
            )
            barrier()
            try dispatch("vector_scale_fast48_kernel", count: count, buffers: [
                (0, inverseNorm, 0), (1, work, 0), (2, basis[column + 1], 0),
            ], countIndex: 3)
            barrier()
        }

        var strideValue = UInt32(stride)
        let backsolve = try pipeline("gmres_backsolve_fast48_kernel")
        encoder.setComputePipelineState(backsolve)
        encoder.setBuffer(h, offset: 0, index: 0)
        encoder.setBuffer(g, offset: 0, index: 1)
        encoder.setBuffer(y, offset: 0, index: 2)
        encoder.setBuffer(completed, offset: 0, index: 3)
        encoder.setBytes(&strideValue, length: 4, index: 4)
        encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        barrier()
        for index in 0..<maxIterations {
            try dispatch("axpy_kernel", count: count, buffers: [
                (0, y, index * MemoryLayout<UInt64>.stride),
                (1, basis[index], 0), (2, x, 0), (3, x, 0),
            ], countIndex: 4)
            barrier()
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
        let completedValue: [UInt32] = read(completed, count: 1)
        let residualBits: [UInt64] = read(convergedResidual, count: 1)
        let observedIterations = Int(completedValue[0])
        guard observedIterations > 0, observedIterations <= maxIterations else {
            throw HarnessError.commandEncoding(
                "device GMRES returned invalid iteration count \(observedIterations)"
            )
        }
        let bNorm = sqrt(b.reduce(0.0) { $0 + $1 * $1 })
        return (
            outputBits.map(Double.init(bitPattern:)),
            observedIterations,
            Double(bitPattern: residualBits[0]) / bNorm,
            wallSeconds
        )
    }
}
