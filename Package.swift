// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Filelay",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Filelay", targets: ["Filelay"])
    ],
    targets: [
        .executableTarget(
            name: "Filelay",
            path: "Sources/Filelay"
        ),
        .testTarget(
            name: "FilelayTests",
            dependencies: ["Filelay"],
            path: "Tests/FilelayTests"
        )
    ]
)
