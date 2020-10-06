// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ZenMQTT",
    products: [
        .library(
            name: "ZenMQTT",
            targets: ["ZenMQTT"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.23.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.9.2"),
    ],
    targets: [
        .target(
            name: "ZenMQTT",
            dependencies: [
                "NIO",
                "NIOSSL"
            ]
        ),
        .testTarget(
            name: "ZenMQTTTests",
            dependencies: ["ZenMQTT"]),
    ]
)
