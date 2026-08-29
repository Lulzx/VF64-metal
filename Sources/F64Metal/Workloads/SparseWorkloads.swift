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

func runScientificWorkloads(_ harness: MetalHarness) throws {
    print("Scientific workload pilot; GPU kernels have no CPU arithmetic fallback")
    try runCSRWorkload(harness, workload: sparseStencilWorkload())
    try runCSRWorkload(harness, workload: denseGEMVWorkload())
}
