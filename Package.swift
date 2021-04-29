// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "RMQClient",
    platforms: [.iOS(.v9), .macOS(.v10_10), .tvOS(.v9)],
    products: [
        .library(
            name: "RMQClient",
            targets: ["RMQClient"])
    ],
    dependencies: [
        .package(url: "https://github.com/robbiehanson/CocoaAsyncSocket", from: "7.6.5"),
        .package(url: "https://github.com/frizzle/JKVValue", .branch("feature/spm-support")),
    ],
    targets: [
        .target(
            name: "RMQClient",
            dependencies: [
                .product(name: "CocoaAsyncSocket", package: "CocoaAsyncSocket"),
                .product(name: "JKVValue", package: "JKVValue"),
            ],
            path: "RMQClient",
            publicHeadersPath: "Source",
            cSettings: [
                .headerSearchPath(""),
                .headerSearchPath("Source")
            ])
    ]
)
