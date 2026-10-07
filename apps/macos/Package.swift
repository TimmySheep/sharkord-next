// swift-tools-version:5.10
import PackageDescription

// macOS native client. SharkordCore is the transport + session layer that the app (and,
// later, the iOS target) consumes; SharkordMac is the SwiftUI application. WKWebView is
// limited to the bundled mediasoup media worker; the rest of the interface remains native.
let package = Package(
    name: "SharkordMac",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10)
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
                "README.md",
                "package-app.sh"
            ],
            sources: ["Sources/SharkordMac"],
            resources: [
                .copy("Resources/locales"),
                .copy("Resources/cove.icns"),
                .copy("Resources/cove-icon.png"),
                .copy("Resources/voice-media"),
                .copy("Resources/AppInfo.plist"),
                .copy("Resources/cs.lproj"),
                .copy("Resources/de.lproj"),
                .copy("Resources/en.lproj"),
                .copy("Resources/es.lproj"),
                .copy("Resources/fr.lproj"),
                .copy("Resources/it.lproj"),
                .copy("Resources/pt-BR.lproj"),
                .copy("Resources/ru.lproj"),
                .copy("Resources/zh-Hans.lproj"),
                .copy("Resources/zh-Hant.lproj")
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
