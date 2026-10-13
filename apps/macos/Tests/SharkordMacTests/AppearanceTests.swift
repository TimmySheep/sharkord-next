import AppKit
import XCTest
@testable import SharkordMac

final class AppearanceTests: XCTestCase {
    func testDesktopAppearanceIsDarkRegardlessOfSavedPreference() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = packageRoot.appendingPathComponent("Sources/SharkordMac/SharkordMacApp.swift")
        let source = try String(contentsOf: appSource, encoding: .utf8)

        XCTAssertFalse(source.contains("@AppStorage(\"app.appearance\")"))
        XCTAssertTrue(source.contains(".preferredColorScheme(.dark)"))
        XCTAssertTrue(source.contains("NSApp.appearance = NSAppearance(named: .darkAqua)"))
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
        XCTAssertTrue(source.contains("Text(serverDisplayName)"))
        XCTAssertTrue(source.contains("return \"cove\""))
        XCTAssertTrue(source.contains(".foregroundStyle(.primary)"))
        XCTAssertTrue(source.contains(".textFieldStyle(.roundedBorder)"))
        XCTAssertTrue(source.contains(".environment(\\.colorScheme, .dark)"))
        XCTAssertTrue(source.contains("RadialGradient("))
        XCTAssertTrue(source.contains("AsyncImage(url: serverLogoURL)"))
        XCTAssertTrue(source.contains("L10n.supportedLanguages"))
        XCTAssertTrue(source.contains(".toggleStyle(.switch)"))
        XCTAssertFalse(source.contains("autoLoginDescription"))
        XCTAssertFalse(source.contains(".background(.regularMaterial"))
        XCTAssertFalse(source.contains("Theme.input"))
        XCTAssertFalse(source.contains(".foregroundStyle(.white)"))
        XCTAssertTrue(source.contains("L10n.t(\"optional\", ns: \"connect\")"))
        XCTAssertFalse(source.contains("Native macOS client"))
        XCTAssertFalse(source.contains("Text(\"Sharkord\")"))
        XCTAssertFalse(source.contains("tagline"))
        XCTAssertFalse(source.contains("WebSocket"))
    }

    func testConnectScreenGlowCannotPushTheCardOffCentre() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SharkordMac/ConnectView.swift"),
            encoding: .utf8
        )

        // a sibling gradient wider than the window inflates the ZStack and shifts the card
        XCTAssertTrue(source.contains("private var backgroundGlow"))
        XCTAssertTrue(source.contains(".overlay(alignment: .top)"))
        XCTAssertFalse(source.contains("geometry.size.width * 1.5"))
    }

    func testSelectingAVoiceChannelInTheSidebarJoinsIt() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/SharkordMac/SidebarView.swift"),
            encoding: .utf8
        )

        // the web client joins on the row click, not after a second press in the channel
        XCTAssertTrue(source.contains(".onTapGesture { openChannel(channel) }"))
        XCTAssertTrue(source.contains("voiceMedia.joinVoiceChannel(channel.id)"))
        XCTAssertTrue(source.contains("session.hasChannelPermission(channel.id, .join)"))
    }

    func testLogExportButtonUsesTextWithoutAnIcon() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent("Sources/SharkordMac/DiagnosticLogExportButton.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Text(L10n.t(\"exportLogs\", ns: \"macos\"))"))
        XCTAssertFalse(source.contains("systemImage:"))
    }

    func testMainWindowHasOneUserSettingsEntryPoint() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let mainWindowURL = packageRoot.appendingPathComponent("Sources/SharkordMac/MainWindow.swift")
        let sidebarURL = packageRoot.appendingPathComponent("Sources/SharkordMac/SidebarView.swift")
        let mainWindow = try String(contentsOf: mainWindowURL, encoding: .utf8)
        let sidebar = try String(contentsOf: sidebarURL, encoding: .utf8)

        XCTAssertNil(mainWindow.range(of: "settingsButton", options: .caseInsensitive))
        XCTAssertTrue(sidebar.contains("Image(systemName: \"gearshape\")"))
    }

    func testVoiceSettingsDescribeAndExposeTheDenoisedAudioMix() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = packageRoot.appendingPathComponent("Sources/SharkordMac/VoiceSettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("noiseSuppressionMixDescription"))
        XCTAssertTrue(source.contains("Slider(value: noiseSuppressionMix, in: 0...1, step: 0.01)"))
        XCTAssertTrue(source.contains("voiceMedia.setNoiseSuppressionMix($0)"))
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
