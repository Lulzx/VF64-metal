import Foundation
import Metal

extension MetalHarness {
    /// Device-resident fast48 GMRES(m) with modified Gram-Schmidt. The matrix
    /// is decoded once and the Krylov basis and work vector are kept as
    /// decoded shadows of their binary64 storage values, so Arnoldi results are
    /// bit-identical to the separate SpMV, dot, and orthogonalization kernels.
    /// The GPU selects the converged column, back-substitutes, and assembles
    /// the solution; Arnoldi columns are submitted in chunks of
    /// `chunkColumns`, and submission stops once a finished chunk carries the
    /// device's selection.
    func deviceConvergedFast48GMRES(
        rowOffsets: [UInt32], columns: [UInt32], values: [Double], b: [Double],
        tolerance: Double, maxIterations: Int, chunkColumns: Int = 1
    ) throws -> (
        x: [Double], iterations: Int, residualEstimate: Double, seconds: Double,
        encodedColumns: Int
    ) {
        let count = b.count
        let stride = maxIterations
        let vectorBytes = count * MemoryLayout<SIMD2<Float>>.stride
        let rowBuffer = try buffer(rowOffsets)
        let columnBuffer = try buffer(columns)
        let valueBits = try buffer(bitsOf(values))
        let valuePairs = try emptyBuffer(count: values.count, of: SIMD2<Float>.self)
        let bBits = try buffer(bitsOf(b))
        let bPairs = try emptyBuffer(count: count, of: SIMD2<Float>.self)
        let x = try buffer(bitsOf([Double](repeating: 0, count: count)))
        let work = try emptyBuffer(count: count, of: SIMD2<Float>.self)
        let basis = try emptyBuffer(
            count: (maxIterations + 1) * count, of: SIMD2<Float>.self
        )
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

        let start = ContinuousClock.now
        let submission = try DeviceTerminatedSubmission(
            queue: queue, label: "vf64:fused_gmres", completed: completed
        )
        let krylov = try KrylovEncoding(
            harness: self, submission: submission, count: count
        )
        let n = UInt32(count)
        try krylov.decode(valueBits, into: valuePairs, elements: values.count)
        try krylov.decode(bBits, into: bPairs, elements: count)
        try krylov.dot(bPairs, bPairs, into: normSquared)
        try krylov.dispatch("gmres_initialize_fast48_kernel", elements: 1, [
            (0, normSquared, 0), (1, inverseNorm, 0), (2, g, 0),
            (3, initialNorm, 0),
        ])
        try krylov.dispatch("krylov_scale_fast48_kernel", elements: count, [
            (0, inverseNorm, 0), (1, bPairs, 0), (2, basis, 0),
        ], words: [(3, n)])

        func encodeColumn(_ column: Int) throws {
            try krylov.dispatch("krylov_spmv_fast48_kernel", elements: count, [
                (0, rowBuffer, 0), (1, columnBuffer, 0), (2, valuePairs, 0),
                (3, basis, column * vectorBytes), (4, work, 0),
            ], words: [(5, n)])
            for row in 0...column {
                let coefficientOffset = (row * stride + column) * MemoryLayout<UInt64>.stride
                try krylov.dot(
                    basis, work, aOffset: row * vectorBytes,
                    into: h, offset: coefficientOffset
                )
                try krylov.dispatch("gmres_orthogonalize_shadow_fast48_kernel", elements: count, [
                    (0, h, coefficientOffset), (1, basis, row * vectorBytes),
                    (2, work, 0),
                ], words: [(3, n)])
            }
            try krylov.dot(work, work, into: normSquared)
            let finalize = try pipeline("gmres_finalize_column_fast48_kernel")
            krylov.encoder.setComputePipelineState(finalize)
            krylov.bind([
                (0, h, 0), (1, normSquared, 0), (2, cosine, 0), (3, sine, 0),
                (4, g, 0), (5, inverseNorm, 0), (6, initialNorm, 0),
                (7, completed, 0), (8, convergedResidual, 0),
            ], words: [(9, UInt32(column)), (10, UInt32(stride))],
               floats: [(11, Float(tolerance))])
            krylov.encoder.dispatchThreads(
                MTLSize(width: 1, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
            )
            krylov.barrier()
            try krylov.dispatch("krylov_scale_fast48_kernel", elements: count, [
                (0, inverseNorm, 0), (1, work, 0),
                (2, basis, (column + 1) * vectorBytes),
            ], words: [(3, n)])
        }

        var encodedColumns = 0
        while encodedColumns < maxIterations {
            let chunkEnd = min(maxIterations, encodedColumns + chunkColumns)
            while encodedColumns < chunkEnd {
                try encodeColumn(encodedColumns)
                encodedColumns += 1
            }
            if try submission.commitChunk() { break }
        }
        let backsolve = try pipeline("gmres_backsolve_fast48_kernel")
        krylov.encoder.setComputePipelineState(backsolve)
        krylov.bind([
            (0, h, 0), (1, g, 0), (2, y, 0), (3, completed, 0),
        ], words: [(4, UInt32(stride))])
        krylov.encoder.dispatchThreads(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
        )
        krylov.barrier()
        try krylov.dispatch("gmres_assemble_fast48_kernel", elements: count, [
            (0, y, 0), (1, basis, 0), (2, x, 0), (3, completed, 0),
        ], words: [(4, n)])
        try submission.finish()
        let wallSeconds = start.duration(to: .now).seconds

        let outputBits: [UInt64] = read(x, count: count)
        let residualBits: [UInt64] = read(convergedResidual, count: 1)
        let observedIterations = Int(submission.deviceCompleted)
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
            wallSeconds, encodedColumns
        )
    }
}
