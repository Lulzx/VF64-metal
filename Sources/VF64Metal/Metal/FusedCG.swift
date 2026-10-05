import Foundation
import Metal

extension MetalHarness {
    /// Device-resident fast48 CG. The matrix is decoded once, and the
    /// solver-internal vectors r, p, and Ap are kept as decoded shadows of their
    /// binary64 storage values, so every result is bit-identical to the
    /// separate SpMV, dot, scalar, and update kernels. The GPU selects
    /// convergence and snapshots the solution; candidate iterations are
    /// submitted in chunks of `chunkIterations`, and submission stops once a
    /// finished chunk carries the device's selection.
    func deviceConvergedFast48CG(
        rowOffsets: [UInt32], columns: [UInt32], values: [Double], b: [Double],
        tolerance: Double, maxIterations: Int, chunkIterations: Int = 3
    ) throws -> (
        x: [Double], iterations: Int, residualSquared: Double, seconds: Double,
        encodedIterations: Int
    ) {
        let count = b.count
        let rowBuffer = try buffer(rowOffsets)
        let columnBuffer = try buffer(columns)
        let valueBits = try buffer(bitsOf(values))
        let valuePairs = try emptyBuffer(count: values.count, of: SIMD2<Float>.self)
        let bBits = try buffer(bitsOf(b))
        let x = try buffer(bitsOf([Double](repeating: 0, count: count)))
        let solution = try emptyBuffer(count: count, of: UInt64.self)
        let r = try emptyBuffer(count: count, of: SIMD2<Float>.self)
        let p = try emptyBuffer(count: count, of: SIMD2<Float>.self)
        let ap = try emptyBuffer(count: count, of: SIMD2<Float>.self)
        let rrA = try emptyBuffer(count: 1, of: UInt64.self)
        let rrB = try emptyBuffer(count: 1, of: UInt64.self)
        let pAp = try emptyBuffer(count: 1, of: UInt64.self)
        let alpha = try emptyBuffer(count: 1, of: UInt64.self)
        let beta = try emptyBuffer(count: 1, of: UInt64.self)
        let initialRR = try emptyBuffer(count: 1, of: UInt64.self)
        let convergedRR = try emptyBuffer(count: 1, of: UInt64.self)
        let completed = try buffer([UInt32(0)])

        let start = ContinuousClock.now
        let submission = try DeviceTerminatedSubmission(
            queue: queue, label: "vf64:fused_cg", completed: completed
        )
        let krylov = try KrylovEncoding(
            harness: self, submission: submission, count: count
        )
        let n = UInt32(count)
        var currentRR = rrA
        var nextRR = rrB
        try krylov.decode(valueBits, into: valuePairs, elements: values.count)
        try krylov.decode(bBits, into: r, elements: count)
        try krylov.decode(bBits, into: p, elements: count)
        try krylov.dot(r, r, into: currentRR)
        try krylov.dispatch("scalar_copy_fast48_kernel", elements: 1, [
            (0, currentRR, 0), (1, initialRR, 0),
        ])

        func encodeIteration(_ iteration: Int) throws {
            let step = UInt32(iteration + 1)
            try krylov.dispatch("krylov_spmv_fast48_kernel", elements: count, [
                (0, rowBuffer, 0), (1, columnBuffer, 0), (2, valuePairs, 0),
                (3, p, 0), (4, ap, 0),
            ], words: [(5, n)])
            try krylov.dotPartial(p, ap)
            var (partials, partialCount) = try krylov.reduceToFinalGroup()
            try krylov.dispatchGroups("cg_alpha_fast48_kernel", groups: 1, [
                (0, partials, 0), (1, currentRR, 0), (2, pAp, 0), (3, alpha, 0),
            ], words: [(4, partialCount)])
            try krylov.dispatch("cg_update_x_r_shadow_fast48_kernel", elements: count, [
                (0, alpha, 0), (1, p, 0), (2, ap, 0), (3, x, 0), (4, r, 0),
            ], words: [(5, n)])
            try krylov.dotPartial(r, r)
            (partials, partialCount) = try krylov.reduceToFinalGroup()
            try krylov.dispatchGroups("cg_check_beta_fast48_kernel", groups: 1, [
                (0, partials, 0), (1, currentRR, 0), (2, nextRR, 0),
                (3, initialRR, 0), (4, completed, 0), (5, convergedRR, 0),
                (6, beta, 0),
            ], words: [
                (7, partialCount), (8, step), (9, UInt32(maxIterations)),
            ], floats: [(10, Float(tolerance))])
            try krylov.dispatch("cg_snapshot_update_p_fast48_kernel", elements: count, [
                (0, completed, 0), (1, x, 0), (2, solution, 0), (3, beta, 0),
                (4, r, 0), (5, p, 0),
            ], words: [(6, step), (7, n)])
            swap(&currentRR, &nextRR)
        }

        var encodedIterations = 0
        while encodedIterations < maxIterations {
            let chunkEnd = min(maxIterations, encodedIterations + chunkIterations)
            while encodedIterations < chunkEnd {
                try encodeIteration(encodedIterations)
                encodedIterations += 1
            }
            if try submission.commitChunk() { break }
        }
        try submission.finish()
        let wallSeconds = start.duration(to: .now).seconds

        let outputBits: [UInt64] = read(solution, count: count)
        let rrBits: [UInt64] = read(convergedRR, count: 1)
        let observedIterations = Int(submission.deviceCompleted)
        guard observedIterations > 0, observedIterations <= maxIterations else {
            throw HarnessError.commandEncoding(
                "device CG returned invalid iteration count \(observedIterations)"
            )
        }
        return (
            outputBits.map(Double.init(bitPattern:)),
            observedIterations,
            Double(bitPattern: rrBits[0]), wallSeconds, encodedIterations
        )
    }
}
