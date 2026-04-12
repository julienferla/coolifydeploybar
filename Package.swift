// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CoolifyDeployBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CoolifyDeployBar", targets: ["CoolifyDeployBar"]),
    ],
    targets: [
        .executableTarget(
            name: "CoolifyDeployBar",
            path: "Sources/CoolifyDeployBar"
        ),
    ]
)
