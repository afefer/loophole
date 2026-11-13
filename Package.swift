// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Loophole",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Loophole",
            path: "Sources/Loophole"
        ),
        .testTarget(
            name: "LoopholeTests",
            dependencies: ["Loophole"],
            path: "Tests/LoopholeTests"
        ),
    ]
)
