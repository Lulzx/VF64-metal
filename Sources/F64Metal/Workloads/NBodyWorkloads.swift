import Foundation
import Metal

private func nbodyReference(
    px: [Double], py: [Double], pz: [Double], mass: [Double], softening: Double
) -> ([Double], [Double], [Double]) {
    var ax = [Double](repeating: 0, count: px.count)
    var ay = ax
    var az = ax
    for i in px.indices {
        for j in px.indices {
            let dx = px[j] - px[i]
            let dy = py[j] - py[i]
            let dz = pz[j] - pz[i]
            var r2 = softening
            r2.addProduct(dz, dz)
            r2.addProduct(dy, dy)
            r2.addProduct(dx, dx)
            let scale = mass[j] / (r2 * sqrt(r2))
            ax[i].addProduct(dx, scale)
            ay[i].addProduct(dy, scale)
            az[i].addProduct(dz, scale)
        }
    }
    return (ax, ay, az)
}

func runNBodyWorkload(_ harness: MetalHarness) throws {
    let count = 512
    let px = (0..<count).map { sin(Double($0) * 0.71) * 10.0 }
    let py = (0..<count).map { cos(Double($0) * 0.53) * 8.0 }
    let pz = (0..<count).map { sin(Double($0) * 0.37 + 0.2) * 6.0 }
    let mass = (0..<count).map { 0.5 + Double(($0 * 31) % 101) / 101.0 }
    let softening = 1.0e-4
    let pxBuffer = try harness.buffer(bitsOf(px))
    let pyBuffer = try harness.buffer(bitsOf(py))
    let pzBuffer = try harness.buffer(bitsOf(pz))
    let massBuffer = try harness.buffer(bitsOf(mass))
    let softeningBuffer = try harness.buffer(bitsOf([softening]))
    let ax = try harness.emptyBuffer(count: count, of: UInt64.self)
    let ay = try harness.emptyBuffer(count: count, of: UInt64.self)
    let az = try harness.emptyBuffer(count: count, of: UInt64.self)
    let buffers: [(Int, MTLBuffer)] = [
        (0, pxBuffer), (1, pyBuffer), (2, pzBuffer), (3, massBuffer),
        (4, ax), (5, ay), (6, az), (7, softeningBuffer),
    ]
    let cpuStart = ContinuousClock.now
    let reference = nbodyReference(
        px: px, py: py, pz: pz, mass: mass, softening: softening
    )
    let cpuSeconds = cpuStart.duration(to: .now).seconds
    print("\nnbody-force-\(count): \(count * count) softened pair interactions")
    print(String(format: "cpu-fp64    %8.3f ms", cpuSeconds * 1.0e3))
    let modes: [(String, String)] = [
        ("fp32", "nbody_fp32_kernel"),
        ("fast48", "nbody_fast48_kernel"),
        ("wide48", "nbody_wide48_kernel"),
        ("ieee64", "nbody_ieee64_kernel"),
    ]
    for (name, kernel) in modes {
        try harness.run(kernel, count: count, buffers: buffers, countIndex: 8)
        let seconds = try medianTime(trials: 5) {
            try harness.run(kernel, count: count, buffers: buffers, countIndex: 8)
        }
        let observedX: [UInt64] = harness.read(ax, count: count)
        let observedY: [UInt64] = harness.read(ay, count: count)
        let observedZ: [UInt64] = harness.read(az, count: count)
        let scores = [
            zip(observedX, reference.0), zip(observedY, reference.1),
            zip(observedZ, reference.2),
        ].flatMap { pairs in
            pairs.map { accuracyBits(
                got: Double(bitPattern: $0.0), reference: $0.1
            ) }
        }.sorted()
        print(String(
            format: "%-8s    %8.3f ms; p01 %5.2f bits; %.2fx CPU",
            (name as NSString).utf8String!, seconds * 1.0e3,
            percentile(scores, 0.01), cpuSeconds / seconds
        ))
    }
}
