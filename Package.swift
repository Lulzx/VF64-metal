// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VF64-metal",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "vf64-metal", targets: ["F64Metal"]),
    ],
    targets: [
        .executableTarget(
            name: "F64Metal",
            resources: [.copy("Shaders")]
        ),
    ]
)
