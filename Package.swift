// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Ticklet",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "Ticklet", targets: ["Ticklet"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Ticklet",
            path: "Sources/Ticklet"
        ),
        .testTarget(
            name: "TickletTests",
            dependencies: ["Ticklet"],
            path: "Tests/TickletTests"
        )
    ]
)
