// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "calctl",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.14.0"),
    ],
    targets: [
        .executableTarget(
            name: "calctl"
        ),
        .testTarget(
            name: "calctlTests",
            dependencies: [
                "calctl",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: [
                .unsafeFlags(["-suppress-warnings"]),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
