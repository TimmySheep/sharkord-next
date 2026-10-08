import Foundation
import Testing

@testable import SharkordCore

struct ClientLogStoreTests {
    @Test
    func exportsDiagnosticCodesWithoutErrorMessages() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cove-client-log-\(UUID().uuidString)", isDirectory: true)
        let exportURL = directory.appendingPathComponent("export.log")
        let store = ClientLogStore(directoryURL: directory)

        store.recordInfo("session.connect.started")
        store.recordError(
            "trpc.query.users.list",
            error: TRPCClientError(code: "FORBIDDEN", message: "Bearer do-not-export-this-secret")
        )
        try store.exportLogs(to: exportURL)

        let contents = try String(contentsOf: exportURL, encoding: .utf8)
        #expect(contents.contains("event=session.connect.started"))
        #expect(contents.contains("code=trpc.FORBIDDEN"))
        #expect(!contents.contains("do-not-export-this-secret"))
    }

    @Test
    func exportIncludesTheRetainedRotatedFilesInOrder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cove-client-log-rotation-\(UUID().uuidString)", isDirectory: true)
        let exportURL = directory.appendingPathComponent("export.log")
        let store = ClientLogStore(directoryURL: directory, maximumFileSize: 1, retainedArchives: 2)

        store.recordInfo("first.event")
        store.recordInfo("second.event")
        store.recordInfo("third.event")
        try store.exportLogs(to: exportURL)

        let contents = try String(contentsOf: exportURL, encoding: .utf8)
        #expect(contents.contains("event=first.event"))
        #expect(contents.contains("event=second.event"))
        #expect(contents.contains("event=third.event"))
        #expect(contents.range(of: "event=first.event")!.lowerBound < contents.range(of: "event=second.event")!.lowerBound)
        #expect(contents.range(of: "event=second.event")!.lowerBound < contents.range(of: "event=third.event")!.lowerBound)
    }
}
