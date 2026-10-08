import XCTest
@testable import SharkordMac

final class MessageMediaTests: XCTestCase {
    func testFileExtensionsMatchWebAudioAndVideoCategories() {
        let videoExtensions = ["mp4", ".mkv", ".MOV", "avi", "wmv", "flv", "webm", "mpeg", "mpg", "3gp"]
        let audioExtensions = ["mp3", ".wav", ".FLAC", "aac", "ogg", "m4a", "wma", "alac"]

        for fileExtension in videoExtensions {
            XCTAssertEqual(MessageMediaType(fileExtension: fileExtension), .video, fileExtension)
        }

        for fileExtension in audioExtensions {
            XCTAssertEqual(MessageMediaType(fileExtension: fileExtension), .audio, fileExtension)
        }

        XCTAssertNil(MessageMediaType(fileExtension: "pdf"))
        XCTAssertNil(MessageMediaType(fileExtension: ""))
    }

    func testMetadataOnlyAcceptsAudioAndVideoOutsideOpenGraphEntries() throws {
        let url = try XCTUnwrap(URL(string: "https://media.example/clip.mp4"))

        XCTAssertEqual(
            MessageMediaReference.metadata(kind: "media", mediaType: "video", url: url)?.type,
            .video
        )
        XCTAssertEqual(
            MessageMediaReference.metadata(kind: "legacy", mediaType: "audio", url: url)?.type,
            .audio
        )
        XCTAssertNil(MessageMediaReference.metadata(kind: "open_graph", mediaType: "video", url: url))
        XCTAssertNil(MessageMediaReference.metadata(kind: "media", mediaType: "image", url: url))
        XCTAssertNil(MessageMediaReference.metadata(kind: "media", mediaType: "other", url: url))
        XCTAssertNil(MessageMediaReference.metadata(kind: "media", mediaType: "audio", url: nil))
    }

    func testMediaReferencesDeduplicateMatchingTypeAndUrlIgnoringFragment() throws {
        let firstURL = try XCTUnwrap(URL(string: "https://media.example/clip.mp4#player"))
        let duplicateURL = try XCTUnwrap(URL(string: "https://media.example/clip.mp4"))
        let audioURL = try XCTUnwrap(URL(string: "https://media.example/clip.mp4?audio=true"))
        let references = [
            MessageMediaReference(type: .video, url: firstURL),
            MessageMediaReference(type: .video, url: duplicateURL),
            MessageMediaReference(type: .audio, url: duplicateURL),
            MessageMediaReference(type: .video, url: audioURL)
        ]

        XCTAssertEqual(MessageMediaReference.deduplicated(references).count, 3)
    }
}
