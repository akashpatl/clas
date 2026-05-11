// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CLAS",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CLAS", targets: ["CLAS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "CLAS",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/CLAS",
            resources: [
                .process("Resources/logo.png"),
            ]
        ),
    ]
)
