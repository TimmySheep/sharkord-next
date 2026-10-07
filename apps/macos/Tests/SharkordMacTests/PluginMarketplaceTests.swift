import Foundation
import XCTest
@testable import SharkordMac

final class PluginMarketplaceTests: XCTestCase {
    func testVersionOrderingHandlesPartialVersionsAndPrereleases() {
        XCTAssertTrue(MarketplaceVersionOrder.isNewer("v1.2", than: "1.1.9"))
        XCTAssertTrue(MarketplaceVersionOrder.isNewer("2.0.0", than: "2.0.0-rc.2"))
        XCTAssertTrue(MarketplaceVersionOrder.isNewer("1.0.0-rc.3", than: "1.0.0-rc.2"))
        XCTAssertFalse(MarketplaceVersionOrder.isNewer("1.0.0-rc.2", than: "1.0.0"))
        XCTAssertFalse(MarketplaceVersionOrder.isNewer("not-a-version", than: "1.0.0"))
    }

    func testMarketplaceDecodeSkipsEntriesWithUnsafeURLs() throws {
        let data = Data(
            #"""
            [
              {"plugin":{"id":"safe-plugin","name":"Safe Plugin","description":"ok","author":"Ada","logo":"https://example.com/logo.png","verified":true},"versions":[{"version":"1.0.0","downloadUrl":"https://example.com/plugin.zip","checksum":"abc","sdkVersion":2,"size":10,"timestamp":1000}]},
              {"plugin":{"id":"unsafe-plugin","name":"Unsafe Plugin","description":"no","author":"Ada","logo":"http://example.com/logo.png","verified":false},"versions":[]}
            ]
            """#.utf8
        )

        let entries = try PluginMarketplaceCatalog.decode(data)

        XCTAssertEqual(entries.map(\.plugin.id), ["safe-plugin"])
        XCTAssertEqual(PluginMarketplaceCatalog.compatibleVersion(in: entries[0])?.version, "1.0.0")
    }

    func testCurrentPluginSDKVersionMatchesTheSharedProtocolConstant() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifest = repositoryRoot.appendingPathComponent("packages/shared/src/plugins/manifest.ts")
        let source = try String(contentsOf: manifest, encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #"PLUGIN_SDK_VERSION\s*=\s*(\d+)"#)
        let range = NSRange(source.startIndex..., in: source)
        let match = try XCTUnwrap(pattern.firstMatch(in: source, range: range))
        let valueRange = try XCTUnwrap(Range(match.range(at: 1), in: source))

        XCTAssertEqual(Int(source[valueRange]), PluginMarketplaceCatalog.sdkVersion)
    }
}
