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
    targets: [
        .target(
            name: "RMQClient",
            path: "RMQClient",
            publicHeadersPath: ".")
    ]
)
