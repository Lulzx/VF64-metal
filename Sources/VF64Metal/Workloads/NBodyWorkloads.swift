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
    try runNBodySimulation(harness)
}

private func nbodyEnergy(
    px: [Double], py: [Double], pz: [Double], vx: [Double], vy: [Double],
    vz: [Double], mass: [Double], softening: Double
) -> Double {
    var energy = 0.0
    for i in px.indices {
        energy += 0.5 * mass[i] * (vx[i] * vx[i] + vy[i] * vy[i] + vz[i] * vz[i])
        for j in (i + 1)..<px.count {
            let dx = px[j] - px[i]
            let dy = py[j] - py[i]
            let dz = pz[j] - pz[i]
            energy -= mass[i] * mass[j] /
                sqrt(dx * dx + dy * dy + dz * dz + softening)
        }
    }
    return energy
}

private func runNBodySimulation(_ harness: MetalHarness) throws {
    let count = 256
    let steps = 16
    let dt = 1.0e-3
    let softening = 1.0e-4
    let initialPX = (0..<count).map { sin(Double($0) * 0.71) * 10.0 }
    let initialPY = (0..<count).map { cos(Double($0) * 0.53) * 8.0 }
    let initialPZ = (0..<count).map { sin(Double($0) * 0.37 + 0.2) * 6.0 }
    let initialVX = (0..<count).map { cos(Double($0) * 0.23) * 0.02 }
    let initialVY = (0..<count).map { sin(Double($0) * 0.31) * 0.02 }
    let initialVZ = (0..<count).map { cos(Double($0) * 0.41) * 0.01 }
    let mass = (0..<count).map { 0.5 + Double(($0 * 31) % 101) / 101.0 }
    let initialEnergy = nbodyEnergy(
        px: initialPX, py: initialPY, pz: initialPZ, vx: initialVX,
        vy: initialVY, vz: initialVZ, mass: mass, softening: softening
    )

    var cpuPX = initialPX, cpuPY = initialPY, cpuPZ = initialPZ
    var cpuVX = initialVX, cpuVY = initialVY, cpuVZ = initialVZ
    let cpuStart = ContinuousClock.now
    for _ in 0..<steps {
        let acceleration = nbodyReference(
            px: cpuPX, py: cpuPY, pz: cpuPZ, mass: mass, softening: softening
        )
        for i in 0..<count {
            cpuVX[i].addProduct(dt, acceleration.0[i])
            cpuVY[i].addProduct(dt, acceleration.1[i])
            cpuVZ[i].addProduct(dt, acceleration.2[i])
            cpuPX[i].addProduct(dt, cpuVX[i])
            cpuPY[i].addProduct(dt, cpuVY[i])
            cpuPZ[i].addProduct(dt, cpuVZ[i])
        }
    }
    let cpuSeconds = cpuStart.duration(to: .now).seconds

    let px = try harness.buffer(bitsOf(initialPX))
    let py = try harness.buffer(bitsOf(initialPY))
    let pz = try harness.buffer(bitsOf(initialPZ))
    let vx = try harness.buffer(bitsOf(initialVX))
    let vy = try harness.buffer(bitsOf(initialVY))
    let vz = try harness.buffer(bitsOf(initialVZ))
    let massBuffer = try harness.buffer(bitsOf(mass))
    let softeningBuffer = try harness.buffer(bitsOf([softening]))
    let dtBuffer = try harness.buffer(bitsOf([dt]))
    let ax = try harness.emptyBuffer(count: count, of: UInt64.self)
    let ay = try harness.emptyBuffer(count: count, of: UInt64.self)
    let az = try harness.emptyBuffer(count: count, of: UInt64.self)
    let gpuSeconds = try harness.runFast48NBodySteps(
        count: count, steps: steps, positions: (px, py, pz),
        velocities: (vx, vy, vz), mass: massBuffer,
        softening: softeningBuffer, dt: dtBuffer, acceleration: (ax, ay, az)
    )
    func doubles(_ buffer: MTLBuffer) -> [Double] {
        let bits: [UInt64] = harness.read(buffer, count: count)
        return bits.map(Double.init(bitPattern:))
    }
    let gpuPX = doubles(px), gpuPY = doubles(py), gpuPZ = doubles(pz)
    let gpuVX = doubles(vx), gpuVY = doubles(vy), gpuVZ = doubles(vz)
    let cpuState = cpuPX + cpuPY + cpuPZ + cpuVX + cpuVY + cpuVZ
    let gpuState = gpuPX + gpuPY + gpuPZ + gpuVX + gpuVY + gpuVZ
    var stateErrorSquared = 0.0
    var stateNormSquared = 0.0
    for index in cpuState.indices {
        let difference = gpuState[index] - cpuState[index]
        stateErrorSquared += difference * difference
        stateNormSquared += cpuState[index] * cpuState[index]
    }
    let stateError = sqrt(stateErrorSquared / stateNormSquared)
    let cpuEnergy = nbodyEnergy(
        px: cpuPX, py: cpuPY, pz: cpuPZ, vx: cpuVX, vy: cpuVY, vz: cpuVZ,
        mass: mass, softening: softening
    )
    let gpuEnergy = nbodyEnergy(
        px: gpuPX, py: gpuPY, pz: gpuPZ, vx: gpuVX, vy: gpuVY, vz: gpuVZ,
        mass: mass, softening: softening
    )
    let cpuDrift = abs((cpuEnergy - initialEnergy) / initialEnergy)
    let gpuDrift = abs((gpuEnergy - initialEnergy) / initialEnergy)
    guard stateError <= 1.0e-10, gpuDrift <= cpuDrift + 1.0e-10 else {
        throw HarnessError.commandEncoding(
            "fast48 N-body simulation contract failed: state error \(stateError), energy drift \(gpuDrift)"
        )
    }
    print("\nnbody-simulation-\(count): \(steps) symplectic-Euler steps")
    print(String(
        format: "cpu-fp64    %8.3f ms; relative energy drift %.3e",
        cpuSeconds * 1.0e3, cpuDrift
    ))
    print(String(
        format: "fast48-gpu  %8.3f ms; state error %.3e; relative energy drift %.3e; %.2fx CPU",
        gpuSeconds * 1.0e3, stateError, gpuDrift, cpuSeconds / gpuSeconds
    ))
}
