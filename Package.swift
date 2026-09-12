// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Diorama",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Diorama", targets: ["Diorama"])],
    targets: [
        .target(name: "CGVirtualDisplayShim", linkerSettings: [.linkedFramework("CoreGraphics")]),
        .target(name: "DioramaCore"),
        .executableTarget(
            name: "Diorama",
            dependencies: ["DioramaCore", "CGVirtualDisplayShim"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ScreenCaptureKit"), .linkedFramework("ApplicationServices")]
        ),
        .testTarget(name: "DioramaCoreTests", dependencies: ["DioramaCore"]),
        .testTarget(name: "DioramaTests", dependencies: ["Diorama"])
    ]
)
