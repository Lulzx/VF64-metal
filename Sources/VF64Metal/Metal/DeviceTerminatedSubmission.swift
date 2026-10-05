import Foundation
import Metal

/// Submits pre-encoded solver steps in a short pipeline of command buffers and
/// stops encoding once a device-written completion word becomes nonzero.
///
/// Convergence is still selected on the GPU: the device writes the completed
/// iteration and snapshots its state. The host only reads that word after a
/// chunk has finished, to stop submitting candidate steps the device has
/// already rejected. It never supplies an iteration count. `depth` chunks stay
/// in flight so the GPU does not idle while the host checks the word.
final class DeviceTerminatedSubmission {
    private let queue: MTLCommandQueue
    private let label: String
    private let completed: MTLBuffer
    private let depth: Int
    private var pending: [MTLCommandBuffer] = []
    private(set) var encoder: MTLComputeCommandEncoder
    private var command: MTLCommandBuffer
    private(set) var committedChunks = 0

    init(
        queue: MTLCommandQueue, label: String, completed: MTLBuffer,
        depth: Int = 2
    ) throws {
        self.queue = queue
        self.label = label
        self.completed = completed
        self.depth = max(1, depth)
        (command, encoder) = try Self.begin(queue: queue, label: label)
    }

    private static func begin(
        queue: MTLCommandQueue, label: String
    ) throws -> (MTLCommandBuffer, MTLComputeCommandEncoder) {
        guard let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else {
            throw HarnessError.commandEncoding("could not encode \(label)")
        }
        command.label = label
        encoder.label = label
        return (command, encoder)
    }

    var deviceCompleted: UInt32 {
        completed.contents().load(as: UInt32.self)
    }

    /// Commits the current chunk. Returns true once a finished chunk shows
    /// that the device has selected convergence; the caller then stops
    /// encoding candidate steps and calls `finish`.
    func commitChunk() throws -> Bool {
        encoder.endEncoding()
        command.commit()
        pending.append(command)
        committedChunks += 1
        (command, encoder) = try Self.begin(queue: queue, label: label)
        while pending.count >= depth {
            let oldest = pending.removeFirst()
            oldest.waitUntilCompleted()
            if let error = oldest.error {
                throw HarnessError.commandEncoding(error.localizedDescription)
            }
            if deviceCompleted != 0 { return true }
        }
        return false
    }

    /// Commits whatever is encoded and waits for every chunk in flight.
    func finish() throws {
        encoder.endEncoding()
        command.commit()
        pending.append(command)
        committedChunks += 1
        for buffer in pending {
            buffer.waitUntilCompleted()
            if let error = buffer.error {
                throw HarnessError.commandEncoding(error.localizedDescription)
            }
        }
        pending.removeAll()
    }
}
