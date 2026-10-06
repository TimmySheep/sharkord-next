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
            dependencies: ["SharkordCore"]
        ),
        .testTarget(
            name: "SharkordCoreTests",
            dependencies: ["SharkordCore"]
        )
    ]
)
