import Foundation
import Testing
@testable import SharkordCore

struct AttachmentUploadPolicyTests {
    private func settings(_ extra: String = "") throws -> SharkordSettings {
        try JSONDecoder().decode(SharkordSettings.self, from: Data("""
        {"name":"test","serverId":"test","storageUploadEnabled":true,
         "storageMaxFilesPerMessage":2,"storageUploadMaxFileSize":10\(extra)}
        """.utf8))
    }

    @Test func uploadGatesUsePermissionsSettingsCountAndBytes() throws {
        let enabled = try settings()
        #expect(AttachmentUploadPolicy.rejection(settings: enabled, canSend: true, canUpload: true, isDM: false, fileCount: 2, fileSize: 10) == nil)
        #expect(AttachmentUploadPolicy.rejection(settings: enabled, canSend: false, canUpload: true, isDM: false, fileCount: 1) == .permission)
        #expect(AttachmentUploadPolicy.rejection(settings: enabled, canSend: true, canUpload: false, isDM: false, fileCount: 1) == .permission)
        #expect(AttachmentUploadPolicy.rejection(settings: nil, canSend: true, canUpload: true, isDM: false, fileCount: 1) == .disabled)
        #expect(AttachmentUploadPolicy.rejection(settings: enabled, canSend: true, canUpload: true, isDM: true, fileCount: 1) == .directMessage)
        let dms = try settings(",\"storageFileSharingInDirectMessages\":true")
        #expect(AttachmentUploadPolicy.rejection(settings: dms, canSend: true, canUpload: true, isDM: true, fileCount: 1) == nil)
        #expect(AttachmentUploadPolicy.rejection(settings: enabled, canSend: true, canUpload: true, isDM: false, fileCount: 3) == .count)
        #expect(AttachmentUploadPolicy.rejection(settings: enabled, canSend: true, canUpload: true, isDM: false, fileCount: 1, fileSize: 11) == .size)
    }
}
