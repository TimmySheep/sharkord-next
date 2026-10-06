// swift-tools-version:5.10
import PackageDescription

// macOS native client. SharkordCore is the transport + session layer that the app (and,
// later, the iOS target) consumes; SharkordMac is the SwiftUI application. Everything is
// plain SwiftUI/AppKit, no embedded web view, per docs/NATIVE_STRATEGY.md.
let package = Package(
    name: "SharkordMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SharkordMac", targets: ["SharkordMac"]),
        .library(name: "SharkordCore", targets: ["SharkordCore"])
    ],
    targets: [
        .target(
            name: "SharkordCore"
        ),
        .executableTarget(
            name: "SharkordMac",
            dependencies: ["SharkordCore"],
            // resources live next to Sources/, not inside it, so the locale tree can be
            // re-copied from the web client in one place. swiftPM only allows resources
            // under the target directory, so the target claims the package root and the
            // compiled sources are named explicitly
            path: ".",
            exclude: [
                "Sources/SharkordCore",
                "Tests",
                "README.md"
            ],
            sources: ["Sources/SharkordMac"],
            resources: [
                .copy("Resources/locales")
            ]
        ),
        .testTarget(
            name: "SharkordCoreTests",
            dependencies: ["SharkordCore"]
        ),
        .testTarget(
            name: "SharkordMacTests",
            dependencies: ["SharkordMac"]
        )
    ]
)
