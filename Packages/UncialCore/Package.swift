// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UncialCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UncialCore", targets: ["UncialCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark.git", branch: "gfm"),
    ],
    targets: [
        .target(
            name: "UncialCore",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ]
        ),
        .testTarget(
            name: "UncialCoreTests",
            dependencies: ["UncialCore"]
        ),
    ]
)
