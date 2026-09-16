// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Diorama",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Diorama", targets: ["Diorama"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4")
    ],
    targets: [
        .target(name: "CGVirtualDisplayShim", linkerSettings: [.linkedFramework("CoreGraphics")]),
        .target(name: "DioramaCore"),
        .executableTarget(
            name: "Diorama",
            dependencies: ["DioramaCore", "CGVirtualDisplayShim", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                .linkedFramework("AppKit"), .linkedFramework("ScreenCaptureKit"), .linkedFramework("ApplicationServices"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(name: "DioramaCoreTests", dependencies: ["DioramaCore"]),
        .testTarget(name: "DioramaTests", dependencies: ["Diorama"])
    ]
)
