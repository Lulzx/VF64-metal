import Foundation
import Metal

private struct CSRWorkload {
    let name: String
    let rows: Int
    let columns: Int
    let rowOffsets: [UInt32]
    let columnIndices: [UInt32]
    let values: [Double]
    let x: [Double]

    var nonzeros: Int { values.count }

    func cpuReference() -> [Double] {
        (0..<rows).map { row in
            var accumulator = 0.0
            for entry in Int(rowOffsets[row])..<Int(rowOffsets[row + 1]) {
                accumulator.addProduct(
                    values[entry], x[Int(columnIndices[entry])]
                )
            }
            return accumulator
        }
    }
}

private func sparseStencilWorkload(size: Int = 65_536) -> CSRWorkload {
    let offsets = [-32, -8, -2, -1, 0, 1, 2, 8, 32]
    var rowOffsets: [UInt32] = [0]
    var columns: [UInt32] = []
    var values: [Double] = []
    for row in 0..<size {
        for offset in offsets {
            let column = (row + offset + size) % size
            columns.append(UInt32(column))
            values.append(offset == 0 ? 4.0 : -0.125)
        }
        rowOffsets.append(UInt32(columns.count))
    }
    let x = (0..<size).map {
        sin(Double($0) * 0.001) + cos(Double($0) * 0.00037)
    }
    return CSRWorkload(
        name: "spmv-cyclic-9", rows: size, columns: size,
        rowOffsets: rowOffsets, columnIndices: columns, values: values, x: x
    )
}

private func denseGEMVWorkload(rows: Int = 1024, columns: Int = 2048) -> CSRWorkload {
    var rowOffsets: [UInt32] = [0]
    var indices: [UInt32] = []
    var values: [Double] = []
    indices.reserveCapacity(rows * columns)
    values.reserveCapacity(rows * columns)
    for row in 0..<rows {
        for column in 0..<columns {
            indices.append(UInt32(column))
            let phase = Double((row * 17 + column * 13) % 1021) * 0.002
            values.append(sin(phase) * 0.03125)
        }
        rowOffsets.append(UInt32(indices.count))
    }
    let x = (0..<columns).map { cos(Double($0) * 0.003) }
    return CSRWorkload(
        name: "gemv-dense-1024x2048", rows: rows, columns: columns,
        rowOffsets: rowOffsets, columnIndices: indices, values: values, x: x
    )
}

private func runCSRWorkload(
    _ harness: MetalHarness, workload: CSRWorkload
) throws {
    let rowBuffer = try harness.buffer(workload.rowOffsets)
    let columnBuffer = try harness.buffer(workload.columnIndices)
    let valueBuffer = try harness.buffer(bitsOf(workload.values))
    let xBuffer = try harness.buffer(bitsOf(workload.x))
    let output = try harness.emptyBuffer(count: workload.rows, of: UInt64.self)
    let buffers: [(Int, MTLBuffer)] = [
        (0, rowBuffer), (1, columnBuffer), (2, valueBuffer),
        (3, xBuffer), (4, output),
    ]

    let cpuStart = ContinuousClock.now
    let reference = workload.cpuReference()
    let cpuSeconds = cpuStart.duration(to: .now).seconds
    print("\n\(workload.name): \(workload.rows) rows, \(workload.columns) columns, \(workload.nonzeros) nonzeros")
    print(String(format: "cpu-fp64    %8.3f ms", cpuSeconds * 1.0e3))

    let modes: [(String, String)] = [
        ("fp32", "spmv_fp32_kernel"),
        ("fast48", "spmv_fast48_kernel"),
        ("wide48", "spmv_wide48_kernel"),
        ("ieee64", "spmv_ieee64_kernel"),
    ]
    for (name, kernel) in modes {
        _ = try harness.run(
            kernel, count: workload.rows, buffers: buffers, countIndex: 5
        )
        let seconds = try medianTime(trials: 5) {
            try harness.run(
                kernel, count: workload.rows, buffers: buffers, countIndex: 5
            )
        }
        let observedBits: [UInt64] = harness.read(output, count: workload.rows)
        let scores = zip(observedBits, reference).map {
            accuracyBits(got: Double(bitPattern: $0.0), reference: $0.1)
        }.sorted()
        print(String(
            format: "%-8s    %8.3f ms; p01 %5.2f bits; %.2fx CPU",
            (name as NSString).utf8String!, seconds * 1.0e3,
            percentile(scores, 0.01), cpuSeconds / seconds
        ))
    }
}

private struct CGResult {
    let x: [Double]
    let iterations: Int
    let relativeResidual: Double
    let seconds: Double
}

private func l2Norm(_ values: [Double]) -> Double {
    sqrt(values.reduce(0.0) { $0 + $1 * $1 })
}

private func relativeSolutionError(_ got: [Double], _ expected: [Double]) -> Double {
    let error = zip(got, expected).map(-).map { $0 * $0 }.reduce(0, +).squareRoot()
    return error / l2Norm(expected)
}

private func cpuCG(
    workload: CSRWorkload, b: [Double], tolerance: Double, maxIterations: Int
) -> CGResult {
    let start = ContinuousClock.now
    var x = [Double](repeating: 0, count: workload.rows)
    var r = b
    var p = r
    let bNorm = l2Norm(b)
    var rr = r.reduce(0.0) { $0 + $1 * $1 }
    var completed = 0
    for iteration in 0..<maxIterations {
        let ap = (0..<workload.rows).map { row in
            var sum = 0.0
            for entry in Int(workload.rowOffsets[row])..<Int(workload.rowOffsets[row + 1]) {
                sum.addProduct(workload.values[entry], p[Int(workload.columnIndices[entry])])
            }
            return sum
        }
        let pAp = zip(p, ap).reduce(0.0) { $0 + $1.0 * $1.1 }
        let alpha = rr / pAp
        for index in x.indices {
            x[index].addProduct(alpha, p[index])
            r[index].addProduct(-alpha, ap[index])
        }
        let nextRR = r.reduce(0.0) { $0 + $1 * $1 }
        completed = iteration + 1
        if sqrt(nextRR) / bNorm <= tolerance {
            rr = nextRR
            break
        }
        let beta = nextRR / rr
        for index in p.indices { p[index] = r[index] + beta * p[index] }
        rr = nextRR
    }
    return CGResult(
        x: x, iterations: completed, relativeResidual: sqrt(rr) / bNorm,
        seconds: start.duration(to: .now).seconds
    )
}

private func gpuFast48CG(
    _ harness: MetalHarness, workload: CSRWorkload, b: [Double],
    tolerance: Double, maxIterations: Int
) throws -> CGResult {
    let rowBuffer = try harness.buffer(workload.rowOffsets)
    let columnBuffer = try harness.buffer(workload.columnIndices)
    let valueBuffer = try harness.buffer(bitsOf(workload.values))
    let x = try harness.buffer(bitsOf([Double](repeating: 0, count: workload.rows)))
    let r = try harness.buffer(bitsOf(b))
    let p = try harness.buffer(bitsOf(b))
    let ap = try harness.emptyBuffer(count: workload.rows, of: UInt64.self)
    let scalar = try harness.buffer([UInt64(0)])
    let bNorm = l2Norm(b)
    var rr = try harness.dot(a: r, b: r, count: workload.rows).0
    var completed = 0
    let start = ContinuousClock.now
    for iteration in 0..<maxIterations {
        try harness.run("spmv_fast48_kernel", count: workload.rows, buffers: [
            (0, rowBuffer), (1, columnBuffer), (2, valueBuffer), (3, p), (4, ap),
        ], countIndex: 5)
        let pAp = try harness.dot(a: p, b: ap, count: workload.rows).0
        scalar.contents().bindMemory(to: UInt64.self, capacity: 1).pointee =
            (rr / pAp).bitPattern
        try harness.run("cg_update_x_r_fast48_kernel", count: workload.rows, buffers: [
            (0, scalar), (1, p), (2, ap), (3, x), (4, r),
        ], countIndex: 5)
        let nextRR = try harness.dot(a: r, b: r, count: workload.rows).0
        completed = iteration + 1
        if sqrt(nextRR) / bNorm <= tolerance {
            rr = nextRR
            break
        }
        scalar.contents().bindMemory(to: UInt64.self, capacity: 1).pointee =
            (nextRR / rr).bitPattern
        try harness.run("cg_update_p_fast48_kernel", count: workload.rows, buffers: [
            (0, scalar), (1, r), (2, p),
        ], countIndex: 3)
        rr = nextRR
    }
    let observed: [UInt64] = harness.read(x, count: workload.rows)
    return CGResult(
        x: observed.map(Double.init(bitPattern:)), iterations: completed,
        relativeResidual: sqrt(rr) / bNorm,
        seconds: start.duration(to: .now).seconds
    )
}

private func runCGWorkload(_ harness: MetalHarness) throws {
    let workload = sparseStencilWorkload(size: 16_384)
    let expected = (0..<workload.rows).map {
        sin(Double($0) * 0.017) + 0.25 * cos(Double($0) * 0.011)
    }
    let system = CSRWorkload(
        name: workload.name, rows: workload.rows, columns: workload.columns,
        rowOffsets: workload.rowOffsets, columnIndices: workload.columnIndices,
        values: workload.values, x: expected
    )
    let b = system.cpuReference()
    let tolerance = 1.0e-11
    let cpu = cpuCG(workload: system, b: b, tolerance: tolerance, maxIterations: 200)
    let gpu = try gpuFast48CG(
        harness, workload: system, b: b, tolerance: tolerance, maxIterations: 200
    )
    let gpuError = relativeSolutionError(gpu.x, expected)
    guard gpu.relativeResidual <= tolerance, gpuError <= 1.0e-10 else {
        throw HarnessError.commandEncoding(
            "fast48 CG failed convergence contract: residual \(gpu.relativeResidual), error \(gpuError)"
        )
    }
    print("\ncg-cyclic-9: \(workload.rows) unknowns; tolerance \(tolerance)")
    print(String(
        format: "cpu-fp64    %3d iterations; residual %.3e; solution error %.3e; %8.3f ms",
        cpu.iterations, cpu.relativeResidual,
        relativeSolutionError(cpu.x, expected), cpu.seconds * 1.0e3
    ))
    print(String(
        format: "fast48-gpu  %3d iterations; residual %.3e; solution error %.3e; %8.3f ms; %.2fx CPU",
        gpu.iterations, gpu.relativeResidual,
        gpuError, gpu.seconds * 1.0e3,
        cpu.seconds / gpu.seconds
    ))
    print("cg control: CPU computes alpha/beta and checks residual; all O(n) arithmetic is GPU")
}

func runScientificWorkloads(_ harness: MetalHarness) throws {
    print("Scientific workload pilot; GPU kernels have no CPU arithmetic fallback")
    try runCSRWorkload(harness, workload: sparseStencilWorkload())
    try runCSRWorkload(harness, workload: denseGEMVWorkload())
    try runCGWorkload(harness)
}
