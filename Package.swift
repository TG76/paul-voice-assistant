// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Paul",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Paul", targets: ["Paul"]),
    ],
    targets: [
        .executableTarget(
            name: "Paul",
            path: "Paul",
            resources: [
                .process("Assets.xcassets"),
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("AVFoundation"),
            ]
        ),
    ]
)
