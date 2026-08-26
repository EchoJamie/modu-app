// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "MoDu",
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
                .copy("Resources/Mermaid")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
