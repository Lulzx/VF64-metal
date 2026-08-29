// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "f64-metal",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "f64-metal", targets: ["F64Metal"]),
    ],
    targets: [
        .executableTarget(
            name: "F64Metal",
            resources: [.copy("Shaders")]
        ),
    ]
)
