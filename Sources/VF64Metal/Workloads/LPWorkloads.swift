import Foundation
import Metal

private func solveLP2D(
    a: [Double], b: [Double], rhs: [Double], c0: Double, c1: Double
) -> (Double, Double, Double) {
    var candidates: [(Double, Double)] = [(0, 0)]
    for i in a.indices {
        candidates.append((rhs[i] / a[i], 0))
        candidates.append((0, rhs[i] / b[i]))
        for j in (i + 1)..<a.count {
            let determinant = a[i] * b[j] - a[j] * b[i]
            if determinant == 0 { continue }
            candidates.append((
                (rhs[i] * b[j] - rhs[j] * b[i]) / determinant,
                (a[i] * rhs[j] - a[j] * rhs[i]) / determinant
            ))
        }
    }
    var best = (0.0, 0.0, 0.0)
    for (x, y) in candidates where x >= 0 && y >= 0 {
        guard a.indices.allSatisfy({
            a[$0] * x + b[$0] * y <= rhs[$0] + 1.0e-10
        }) else {
            continue
        }
        let objective = c0 * x + c1 * y
        if objective >= best.2 { best = (x, y, objective) }
    }
    return best
}

private struct LP2DCorpusCase {
    let name: String
    let a: [Double]
    let b: [Double]
    let rhs: [Double]
}

private func lp2DCorpus() -> [LP2DCorpusCase] {
    let baseA = [1.0, 0.25, 1.5, 0.7, 1.2, 0.4, 1.8, 0.9]
    let baseB = [0.2, 1.0, 0.6, 1.4, 0.35, 1.7, 0.8, 1.1]
    let baseRHS = [5.0, 4.5, 6.8, 6.2, 5.7, 6.5, 7.4, 5.9]
    let scales = [1.0 / 4096.0, 1.0 / 64.0, 0.25, 1.0, 4.0, 32.0, 256.0, 4096.0]
    return [
        LP2DCorpusCase(name: "bounded-8", a: baseA, b: baseB, rhs: baseRHS),
        LP2DCorpusCase(
            name: "near-parallel-8",
            a: [1.0, 1.01, 0.99, 0.4, 1.6, 0.75, 1.25, 0.2],
            b: [1.0, 0.99, 1.01, 1.6, 0.4, 1.25, 0.75, 1.8],
            rhs: [6.0, 6.02, 6.01, 6.4, 6.5, 6.2, 6.3, 6.8]
        ),
        LP2DCorpusCase(
            name: "redundant-12",
            a: baseA + [2.0, 0.5, 3.0, 1.4],
            b: baseB + [0.4, 2.0, 1.2, 2.8],
            rhs: baseRHS + [10.5, 9.5, 14.5, 13.0]
        ),
        LP2DCorpusCase(
            name: "scaled-8",
            a: zip(baseA, scales).map { $0.0 * $0.1 },
            b: zip(baseB, scales).map { $0.0 * $0.1 },
            rhs: zip(baseRHS, scales).map { $0.0 * $0.1 }
        ),
    ]
}

private func runLP2DCase(
    _ problem: LP2DCorpusCase, problemCount: Int, seedOffset: Int,
    harness: MetalHarness
) throws {
    precondition(problem.a.count == problem.b.count && problem.a.count == problem.rhs.count)
    let c0 = (0..<problemCount).map {
        0.5 + Double((($0 + seedOffset) * 17) % 997) / 997.0
    }
    let c1 = (0..<problemCount).map {
        0.5 + Double((($0 + seedOffset) * 29) % 991) / 991.0
    }
    let buffers: [(Int, MTLBuffer)] = try [
        (0, harness.buffer(bitsOf(problem.a))), (1, harness.buffer(bitsOf(problem.b))),
        (2, harness.buffer(bitsOf(problem.rhs))), (3, harness.buffer(bitsOf(c0))),
        (4, harness.buffer(bitsOf(c1))),
    ] + [
        (5, harness.emptyBuffer(count: problemCount * 3, of: UInt64.self)),
        (6, harness.buffer([UInt32(problem.a.count)])),
    ]
    let output = buffers.first(where: { $0.0 == 5 })!.1
    let cpuStart = ContinuousClock.now
    let reference = (0..<problemCount).map {
        solveLP2D(
            a: problem.a, b: problem.b, rhs: problem.rhs,
            c0: c0[$0], c1: c1[$0]
        )
    }
    let cpuSeconds = cpuStart.duration(to: .now).seconds
    print(
        "\nlp-batch-2d/\(problem.name): \(problemCount) bounded LPs; " +
        "\(problem.a.count) inequalities each"
    )
    print(String(format: "cpu-fp64    %8.3f ms", cpuSeconds * 1.0e3))
    for (name, kernel) in [("fast48", "lp_fast48_kernel"), ("ieee64", "lp_ieee64_kernel")] {
        try harness.run(kernel, count: problemCount, buffers: buffers, countIndex: 7)
        let seconds = try medianTime(trials: 5) {
            try harness.run(kernel, count: problemCount, buffers: buffers, countIndex: 7)
        }
        let observed: [UInt64] = harness.read(output, count: problemCount * 3)
        let scores = reference.indices.map { index in
            accuracyBits(
                got: Double(bitPattern: observed[index * 3 + 2]),
                reference: reference[index].2
            )
        }.sorted()
        let infeasible = reference.indices.filter { index in
            let x = Double(bitPattern: observed[index * 3])
            let y = Double(bitPattern: observed[index * 3 + 1])
            return x < 0 || y < 0 || problem.a.indices.contains {
                problem.a[$0] * x + problem.b[$0] * y > problem.rhs[$0] + 1.0e-10
            }
        }.count
        guard infeasible == 0 else {
            throw HarnessError.commandEncoding("\(name) LP returned \(infeasible) infeasible optima")
        }
        print(String(
            format: "%-8s    %8.3f ms; objective p01 %5.2f bits; %.2fx CPU",
            (name as NSString).utf8String!, seconds * 1.0e3,
            percentile(scores, 0.01), cpuSeconds / seconds
        ))
    }
}

func runLPWorkload(_ harness: MetalHarness) throws {
    let problemCount = 4_096
    for (index, problem) in lp2DCorpus().enumerated() {
        try runLP2DCase(
            problem, problemCount: problemCount,
            seedOffset: index * problemCount, harness: harness
        )
    }
}
