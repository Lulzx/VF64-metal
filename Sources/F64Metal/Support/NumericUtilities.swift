import Foundation

extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1.0e18
    }
}

func bitsOf(_ values: [Double]) -> [UInt64] {
    values.map(\.bitPattern)
}

func accuracyBits(got: Double, reference: Double) -> Double {
    if got.bitPattern == reference.bitPattern { return 64 }
    if got.isNaN && reference.isNaN { return 64 }
    if !got.isFinite || !reference.isFinite { return 0 }
    let error = abs(got - reference)
    if error == 0 { return 64 }
    let scale = max(abs(reference), Double.leastNormalMagnitude)
    return max(0, min(64, -Foundation.log2(error / scale)))
}

func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
    guard !sorted.isEmpty else { return .nan }
    return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction))]
}

func medianTime(trials: Int = 5, _ operation: () throws -> Double) rethrows -> Double {
    var values: [Double] = []
    for _ in 0..<trials { values.append(try operation()) }
    values.sort()
    return values[values.count / 2]
}

func splitPairs(_ values: [Double]) -> [SIMD2<Float>] {
    values.map { value in
        let hi = Float(value)
        let lo = Float(value - Double(hi))
        return SIMD2<Float>(hi, lo)
    }
}

