import Foundation
import Metal

final class MetalHarness {
    let device: MTLDevice
    let queue: MTLCommandQueue
    private let library: MTLLibrary
    private var pipelines: [String: MTLComputePipelineState] = [:]

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            throw HarnessError.noMetalDevice
        }
        let options = MTLCompileOptions()
        options.languageVersion = .version3_2
        self.device = device
        self.queue = queue
        self.library = try device.makeLibrary(
            source: ShaderSourceLoader.load(), options: options
        )
    }

    func pipeline(_ name: String) throws -> MTLComputePipelineState {
        if let existing = pipelines[name] { return existing }
        guard let function = library.makeFunction(name: name) else {
            throw HarnessError.commandEncoding("shader function \(name) was not found")
        }
        let pipeline = try device.makeComputePipelineState(function: function)
        pipelines[name] = pipeline
        return pipeline
    }

    func buffer<T>(_ values: [T]) throws -> MTLBuffer {
        let length = MemoryLayout<T>.stride * values.count
        guard let result = values.withUnsafeBytes({ bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: length, options: .storageModeShared)
        }) else {
            throw HarnessError.bufferAllocation(length)
        }
        return result
    }

    func emptyBuffer<T>(count: Int, of: T.Type = T.self) throws -> MTLBuffer {
        let length = max(1, MemoryLayout<T>.stride * count)
        guard let result = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw HarnessError.bufferAllocation(length)
        }
        return result
    }

    func read<T>(_ buffer: MTLBuffer, count: Int, as: T.Type = T.self) -> [T] {
        let pointer = buffer.contents().bindMemory(to: T.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    @discardableResult
    func run(
        _ name: String,
        count: Int,
        buffers: [(Int, MTLBuffer)],
        countIndex: Int,
        iterations: Int = 1
    ) throws -> Double {
        let pipeline = try pipeline(name)
        guard let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else {
            throw HarnessError.commandEncoding("could not create command encoder")
        }
        encoder.setComputePipelineState(pipeline)
        for (index, buffer) in buffers { encoder.setBuffer(buffer, offset: 0, index: index) }
        var n = UInt32(count)
        encoder.setBytes(&n, length: MemoryLayout<UInt32>.size, index: countIndex)
        let width = min(
            pipeline.maxTotalThreadsPerThreadgroup,
            max(1, pipeline.threadExecutionWidth * 4)
        )
        let start = ContinuousClock.now
        for _ in 0..<iterations {
            encoder.dispatchThreads(
                MTLSize(width: count, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
            )
        }
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error {
            throw HarnessError.commandEncoding(error.localizedDescription)
        }
        let gpuElapsed = command.gpuEndTime - command.gpuStartTime
        return gpuElapsed > 0 ? gpuElapsed : start.duration(to: .now).seconds
    }
}

