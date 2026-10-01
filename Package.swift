// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Seance",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "GhosttyC",
            path: "Sources/GhosttyC"
        ),
        .executableTarget(
            name: "Seance",
            dependencies: ["GhosttyC"],
            path: "Sources/Seance",
            linkerSettings: [
                .unsafeFlags(["-L", "build/ghostty/lib"]),
                .linkedLibrary("ghostty"),
                .linkedLibrary("c++"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .executableTarget(
            name: "seance-hook",
            path: "Sources/SeanceHook"
        ),
    ]
)
