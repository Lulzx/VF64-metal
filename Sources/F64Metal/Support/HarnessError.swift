import Foundation

enum HarnessError: Error, CustomStringConvertible {
    case noMetalDevice
    case resourceMissing(String)
    case bufferAllocation(Int)
    case commandEncoding(String)
    case validation(String)

    var description: String {
        switch self {
        case .noMetalDevice:
            return "No Metal device is available"
        case .resourceMissing(let name):
            return "Bundled resource \(name) was not found"
        case .bufferAllocation(let bytes):
            return "Could not allocate a \(bytes)-byte Metal buffer"
        case .commandEncoding(let detail):
            return "Metal command failed: \(detail)"
        case .validation(let detail):
            return "Validation failed: \(detail)"
        }
    }
}

