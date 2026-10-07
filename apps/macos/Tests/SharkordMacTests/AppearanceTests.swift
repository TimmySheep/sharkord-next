import XCTest
@testable import SharkordMac

final class AppearanceTests: XCTestCase {
    func testDarkThemePinsDarkSystemColorsForTheWindow() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = packageRoot.appendingPathComponent("Sources/SharkordMac/SharkordMacApp.swift")
        let source = try String(contentsOf: appSource, encoding: .utf8)

        XCTAssertTrue(source.contains(".preferredColorScheme(.dark)"))
    }
}
