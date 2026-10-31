import Foundation
import XCTest
@testable import SharkordCore

final class HTTPUploadTests: XCTestCase {
    func testUploadEncodesTrimmedFilenameLikeTheWebClient() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UploadURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            UploadURLProtocol.inspectRequest = nil
        }
        let client = SharkordHTTPClient(baseURL: URL(string: "https://example.test")!, session: session)

        for (filename, expected) in [
            ("  report 100%.txt \n", "report%20100%25.txt"),
            ("图片 café.png", "%E5%9B%BE%E7%89%87%20caf%C3%A9.png"),
            ("a/b?#&+.txt", "a%2Fb%3F%23%26%2B.txt")
        ] {
            UploadURLProtocol.inspectRequest = { request in
                XCTAssertEqual(request.url?.path, "/upload")
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-file-name"), expected)
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-token"), "test-token")
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-file-type"), "text/plain")
                XCTAssertEqual(request.value(forHTTPHeaderField: "content-length"), "3")
                XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/octet-stream")
            }

            let file = try await client.upload(
                data: Data([0, 127, 255]), fileName: filename, mimeType: "text/plain", token: "test-token"
            )
            XCTAssertEqual(file.id, "temporary-file")
        }
    }
}

private final class UploadURLProtocol: URLProtocol, @unchecked Sendable {
    static var inspectRequest: ((URLRequest) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.inspectRequest?(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let body = Data(#"{"id":"temporary-file","originalName":"file.txt","size":3,"md5":"test","path":"/tmp/file","extension":"txt"}"#.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
