// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Ticklet",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Ticklet", targets: ["Ticklet"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Ticklet",
            path: "Sources/Ticklet",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "TickletTests",
            dependencies: ["Ticklet"],
            path: "Tests/TickletTests"
        )
    ]
)
