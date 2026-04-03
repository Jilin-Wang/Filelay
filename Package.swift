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
            path: "Sources/Filelay",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Support/Filelay-Info.plist",
                ]),
            ]
        ),
        .testTarget(
            name: "FilelayTests",
            dependencies: ["Filelay"],
            path: "Tests/FilelayTests"
        )
    ]
)
