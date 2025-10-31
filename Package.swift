// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftIM",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "SwiftIM",
            targets: ["SwiftIM"]),
    ],
    dependencies: [
        // 网络
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.8.0"),
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0"),
        // 加密
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.8.0"),
        // Protobuf
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.25.0"),
    ],
    targets: [
        .target(
            name: "SwiftIM",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "Starscream", package: "Starscream"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources/IMSDK"
        ),
        .testTarget(
            name: "SwiftIMTests",
            dependencies: ["SwiftIM"],
            path: "Tests/IMSDKTests"
        ),
    ]
)

