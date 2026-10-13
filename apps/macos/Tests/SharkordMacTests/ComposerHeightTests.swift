import AppKit
import SwiftUI
import XCTest
@testable import SharkordMac

@MainActor
final class ComposerHeightTests: XCTestCase {
    private func makeTextView(width: CGFloat = 320) -> ComposerTextView {
        let textView = ComposerTextView(frame: NSRect(x: 0, y: 0, width: width, height: 40))

        textView.font = .systemFont(ofSize: 13.5)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 8, height: 8)

        return textView
    }

    func testAnEmptyComposerStaysAtTheMinimumHeight() {
        let textView = makeTextView()

        XCTAssertEqual(textView.measuredContentHeight(min: 42, max: 150), 42)
    }

    func testWrappedTextGrowsTheComposerWithoutReachingTheMaximum() {
        let textView = makeTextView()
        textView.string = "a\nb\nc\nd"

        let height = textView.measuredContentHeight(min: 42, max: 150)

        XCTAssertGreaterThan(height, 42)
        XCTAssertLessThan(height, 150)
    }

    func testLongTextStopsGrowingAtTheMaximumHeight() {
        let textView = makeTextView()
        textView.string = Array(repeating: "line", count: 60).joined(separator: "\n")

        XCTAssertEqual(textView.measuredContentHeight(min: 42, max: 150), 150)
    }

    func testANarrowerComposerWrapsToMoreLinesThanAWiderOne() {
        let text = String(repeating: "wrapping text ", count: 12)

        let narrow = makeTextView(width: 200)
        narrow.string = text
        let wide = makeTextView(width: 800)
        wide.string = text

        XCTAssertGreaterThan(
            narrow.measuredContentHeight(min: 42, max: 150),
            wide.measuredContentHeight(min: 42, max: 150)
        )
    }

    /// The composer's height comes from the editor's binding, so typing has to publish a new
    /// value through it for the box to grow.
    func testTypingPublishesAGrowingHeightThroughTheBinding() {
        let harness = makeHarness()
        harness.textView.string = "a\nb\nc\nd\ne"

        harness.coordinator.textDidChange(
            Notification(name: NSText.didChangeNotification, object: harness.textView)
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        XCTAssertGreaterThan(harness.box.height, 42)
        XCTAssertEqual(harness.box.text, "a\nb\nc\nd\ne")
    }

    func testTypingStopsAtTheMaximumHeight() {
        let harness = makeHarness()
        harness.textView.string = Array(repeating: "line", count: 60).joined(separator: "\n")

        harness.coordinator.textDidChange(
            Notification(name: NSText.didChangeNotification, object: harness.textView)
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(harness.box.height, 150)
    }

    private final class Harness {
        let box: Box
        let coordinator: ComposerTextEditor.Coordinator
        let textView: NSTextView

        init(box: Box, coordinator: ComposerTextEditor.Coordinator, textView: NSTextView) {
            self.box = box
            self.coordinator = coordinator
            self.textView = textView
        }
    }

    private final class Box {
        var height: CGFloat = 42
        var text = ""
    }

    private func makeHarness() -> Harness {
        let box = Box()
        let editor = ComposerTextEditor(
            text: Binding(get: { box.text }, set: { box.text = $0 }),
            height: Binding(get: { box.height }, set: { box.height = $0 }),
            minHeight: 42,
            maxHeight: 150
        )
        let coordinator = editor.makeCoordinator()

        let textView = makeTextView()
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 42))
        scrollView.documentView = textView

        coordinator.textView = textView
        coordinator.owner = editor
        coordinator.minHeight = 42
        coordinator.maxHeight = 150

        return Harness(box: box, coordinator: coordinator, textView: textView)
    }
}
