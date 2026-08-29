import Foundation

struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    mutating func finiteValue(exponentRange: ClosedRange<Int> = -60...60) -> Double {
        let span = exponentRange.upperBound - exponentRange.lowerBound + 1
        let exponent = exponentRange.lowerBound + Int(next() % UInt64(span))
        let significand = 0.5 + unit() * 0.5
        let sign = (next() & 1) == 0 ? 1.0 : -1.0
        return sign * Foundation.scalbn(significand, Int32(exponent))
    }
}

