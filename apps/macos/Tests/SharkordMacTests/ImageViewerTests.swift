import XCTest
@testable import SharkordMac

final class ImageViewerTests: XCTestCase {
    func testZoomRangeMatchesWebViewerBounds() {
        XCTAssertEqual(ImageViewerZoom.clamped(0.1), 0.5)
        XCTAssertEqual(ImageViewerZoom.clamped(1.4), 1.4)
        XCTAssertEqual(ImageViewerZoom.clamped(5), 3)
    }
}
