// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PatronArchiverKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "PatronArchiverKit",
            targets: ["PatronArchiverKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-http-structured-headers.git", from: "1.6.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "PatronArchiverKit",
            dependencies: [
                .product(name: "RawStructuredFieldValues", package: "swift-http-structured-headers"),
            ],
            resources: [
                .copy("LazyContentLoader/LazyContentLoader.js"),
            ]
        ),
        .testTarget(
            name: "PatronArchiverKitTests",
            dependencies: ["PatronArchiverKit"]
        ),
    ]
)
