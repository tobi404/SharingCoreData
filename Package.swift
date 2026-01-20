// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "sharing-core-data",
    platforms: [
      .iOS(.v13),
      .macOS(.v11),
      .tvOS(.v13),
      .watchOS(.v7),
    ],
    products: [
        .library(
            name: "SharingCoreData",
            targets: ["SharingCoreData"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.6.4"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.3.0")
    ],
    targets: [
        .target(
            name: "SharingCoreData",
            dependencies: [
                .product(name: "Sharing", package: "swift-sharing"),
            ]
        ),
        .testTarget(
            name: "SharingCoreDataTests",
            dependencies: [
                "SharingCoreData",
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
            ]
        ),
    ]
)
