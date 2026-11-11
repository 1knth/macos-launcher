// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Prism",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PrismCore", path: "Sources/PrismCore"),
        .executableTarget(
            name: "Prism",
            dependencies: ["PrismCore"],
            path: "Sources/Prism",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(name: "PrismCoreTests", dependencies: ["PrismCore"], path: "Tests/PrismCoreTests"),
    ]
)
