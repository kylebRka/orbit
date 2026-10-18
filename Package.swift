// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Orbit",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "Orbit", targets: ["Orbit"])],
    targets: [
        .target(name: "OrbitCore"),
        .executableTarget(name: "Orbit", dependencies: ["OrbitCore"]),
        .testTarget(name: "OrbitCoreTests", dependencies: ["OrbitCore"])
    ]
)
