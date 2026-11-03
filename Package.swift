// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Vigil",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "VigilCore",
            linkerSettings: [.linkedLibrary("sqlite3"), .linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "Vigil",
            dependencies: ["VigilCore"],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ServiceManagement")]
        ),
        .testTarget(
            name: "VigilCoreTests",
            dependencies: ["VigilCore"]
        ),
    ]
)
