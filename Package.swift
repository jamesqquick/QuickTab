// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuickTab",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QuickTab", targets: ["QuickTab"]),
    ],
    targets: [
        .executableTarget(
            name: "QuickTab",
            path: "Sources/QuickTab"
        ),
        .testTarget(
            name: "QuickTabTests",
            dependencies: ["QuickTab"],
            path: "Tests/QuickTabTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
