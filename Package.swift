// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuickTab",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QuickTab", targets: ["QuickTab"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.6"),
    ],
    targets: [
        .executableTarget(
            name: "QuickTab",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
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
