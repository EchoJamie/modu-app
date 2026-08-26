// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "MoDu",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-markdown.git",
            exact: "0.7.3"
        )
    ],
    targets: [
        .executableTarget(
            name: "MoDu",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/MoDu",
            resources: [
                .copy("Resources/Mermaid"),
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
