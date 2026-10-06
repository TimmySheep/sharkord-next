import Foundation

/// File deletion, for attachments and for uploads that were never sent.
extension SharkordSession {
    public func deleteFile(fileId: Int) async throws {
        _ = try await call(
            "files.delete",
            method: .mutation,
            input: .object(["fileId": .int(fileId)])
        )
    }

    public func deleteTemporaryFile(fileId: String) async throws {
        _ = try await call(
            "files.deleteTemporary",
            method: .mutation,
            input: .object(["fileId": .string(fileId)])
        )
    }

    /// Uploads one attachment and returns the temp file id `messages.send` expects in `files`.
    public func uploadAttachment(
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> String {
        guard let http, let token else {
            throw TRPCClientError(code: "DISCONNECTED", message: "Not connected")
        }

        let temp = try await http.upload(
            data: data,
            fileName: fileName,
            mimeType: mimeType,
            token: token
        )

        return temp.id
    }
}
