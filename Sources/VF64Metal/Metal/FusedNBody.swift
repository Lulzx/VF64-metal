import Foundation
import Metal

extension MetalHarness {
    func runFast48NBodySteps(
        count: Int, steps: Int,
        positions: (MTLBuffer, MTLBuffer, MTLBuffer),
        velocities: (MTLBuffer, MTLBuffer, MTLBuffer),
        mass: MTLBuffer, softening: MTLBuffer, dt: MTLBuffer,
        acceleration: (MTLBuffer, MTLBuffer, MTLBuffer)
    ) throws -> Double {
        guard let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else {
            throw HarnessError.commandEncoding("could not encode fused N-body steps")
        }
        func dispatch(
            _ name: String, buffers: [(Int, MTLBuffer)], countIndex: Int
        ) throws {
            let state = try pipeline(name)
            encoder.setComputePipelineState(state)
            for (index, value) in buffers {
                encoder.setBuffer(value, offset: 0, index: index)
            }
            var n = UInt32(count)
            encoder.setBytes(&n, length: 4, index: countIndex)
            let width = min(
                state.maxTotalThreadsPerThreadgroup,
                max(1, state.threadExecutionWidth * 4)
            )
            encoder.dispatchThreads(
                MTLSize(width: count, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
            )
        }
        for _ in 0..<steps {
            try dispatch("nbody_fast48_kernel", buffers: [
                (0, positions.0), (1, positions.1), (2, positions.2),
                (3, mass), (4, acceleration.0), (5, acceleration.1),
                (6, acceleration.2), (7, softening),
            ], countIndex: 8)
            encoder.memoryBarrier(scope: .buffers)
            try dispatch("nbody_integrate_fast48_kernel", buffers: [
                (0, dt), (1, acceleration.0), (2, acceleration.1),
                (3, acceleration.2), (4, positions.0), (5, positions.1),
                (6, positions.2), (7, velocities.0), (8, velocities.1),
                (9, velocities.2),
            ], countIndex: 10)
            encoder.memoryBarrier(scope: .buffers)
        }
        encoder.endEncoding()
        let start = ContinuousClock.now
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error {
            throw HarnessError.commandEncoding(error.localizedDescription)
        }
        return start.duration(to: .now).seconds
    }
}
