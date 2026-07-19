// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WakeMyMac",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "wake-my-mac",
            targets: ["WakeMyMac"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.1.0"),
        .package(url: "https://github.com/tuist/Noora", exact: "0.51.3")
    ],
    targets: [
        .executableTarget(
            name: "WakeMyMac",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Noora", package: "Noora")
            ],
            path: "WakeMyMac",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "WakeMyMacTests",
            dependencies: ["WakeMyMac"],
            path: "WakeMyMacTests"
        )
    ]
)
