import AppKit
import XCTest
@testable import SharkordMac

final class AppearanceTests: XCTestCase {
    func testWindowAppearanceUsesTheSavedSystemLightOrDarkPreference() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = packageRoot.appendingPathComponent("Sources/SharkordMac/SharkordMacApp.swift")
        let source = try String(contentsOf: appSource, encoding: .utf8)

        XCTAssertTrue(source.contains("@AppStorage(\"app.appearance\")"))
        XCTAssertTrue(source.contains(".preferredColorScheme(colorScheme)"))
        XCTAssertFalse(source.contains(".preferredColorScheme(.dark)"))
    }

    func testCoveAppIconIsPresent() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let icon = packageRoot.appendingPathComponent("Resources/cove.icns")
        let logo = packageRoot.appendingPathComponent("Resources/cove-icon.png")
        let lightArtwork = packageRoot.appendingPathComponent("Resources/Cove.icon/Assets/Cove-Light.png")
        let darkArtwork = packageRoot.appendingPathComponent("Resources/Cove.icon/Assets/Cove-Dark.png")
        let iconDocument = try String(
            contentsOf: packageRoot.appendingPathComponent("Resources/Cove.icon/icon.json"),
            encoding: .utf8
        )
        let appInfo = try String(
            contentsOf: packageRoot.appendingPathComponent("Resources/AppInfo.plist"),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SharkordMac/SharkordMacApp.swift"),
            encoding: .utf8
        )
        let packageScript = try String(
            contentsOf: packageRoot.appendingPathComponent("package-app.sh"),
            encoding: .utf8
        )
        let manifest = try String(
            contentsOf: packageRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: icon.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logo.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lightArtwork.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: darkArtwork.path))
        XCTAssertTrue(iconDocument.contains("\"appearance\": \"dark\""))
        XCTAssertTrue(appInfo.contains("<key>CFBundleIconName</key>"))
        XCTAssertTrue(appSource.contains("Bundle.main.bundleURL.pathExtension != \"app\""))
        XCTAssertTrue(packageScript.contains("xcrun actool"))
        XCTAssertTrue(
            packageScript.components(separatedBy: "xcrun actool").last?.contains(
                "cp \"$root/Resources/cove.icns\""
            ) == true
        )
        XCTAssertTrue(manifest.contains(".copy(\"Resources/cove-icon.png\")"))
    }

    func testCoveLogoHasTransparentCornersWithoutAnOpaqueBorder() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let logoURL = packageRoot.appendingPathComponent("Resources/cove-icon.png")
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: logoURL)))
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh

        XCTAssertEqual(bitmap.colorAt(x: 0, y: 0)?.alphaComponent, 0)
        XCTAssertEqual(bitmap.colorAt(x: width - 1, y: 0)?.alphaComponent, 0)
        XCTAssertEqual(bitmap.colorAt(x: 0, y: height - 1)?.alphaComponent, 0)
        XCTAssertEqual(bitmap.colorAt(x: width - 1, y: height - 1)?.alphaComponent, 0)

        let leftEdge = try XCTUnwrap(bitmap.colorAt(x: 0, y: height / 2)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(leftEdge.alphaComponent, 1)
        XCTAssertGreaterThan(leftEdge.blueComponent, 0.2)
        XCTAssertEqual(bitmap.colorAt(x: width / 2, y: height / 2)?.alphaComponent, 1)
    }

    func testConnectScreenUsesCoveBrandingAndHidesTechnicalCopy() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent("Sources/SharkordMac/ConnectView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Image(\"cove-icon\", bundle: .module)"))
        XCTAssertTrue(source.contains("Text(\"cove\")"))
        XCTAssertTrue(source.contains(".foregroundStyle(.primary)"))
        XCTAssertTrue(source.contains("Theme.input"))
        XCTAssertFalse(source.contains(".foregroundStyle(.white)"))
        XCTAssertTrue(source.contains("L10n.t(\"optional\", ns: \"connect\")"))
        XCTAssertFalse(source.contains("Native macOS client"))
        XCTAssertFalse(source.contains("Text(\"Sharkord\")"))
        XCTAssertFalse(source.contains("tagline"))
        XCTAssertFalse(source.contains("WebSocket"))
    }

    func testMainWindowDoesNotSetCoveAsItsWindowTitle() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = packageRoot.appendingPathComponent("Sources/SharkordMac/SharkordMacApp.swift")
        let source = try String(contentsOf: appSource, encoding: .utf8)

        XCTAssertTrue(source.contains("WindowGroup(id: \"main\")"))
        XCTAssertFalse(source.contains("WindowGroup(\"Cove\", id: \"main\")"))
    }

    func testElevatedSurfacesUseAppearanceAdaptiveColors() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let designSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SharkordMac/DesignSystem.swift"),
            encoding: .utf8
        )
        let emojiSource = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SharkordMac/EmojiPicker.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(designSource.contains("static let elevated = Color.primary.opacity("))
        XCTAssertFalse(designSource.contains("underPageBackgroundColor"))
        XCTAssertTrue(emojiSource.contains("Color.primary.opacity(0.08)"))
    }
}
