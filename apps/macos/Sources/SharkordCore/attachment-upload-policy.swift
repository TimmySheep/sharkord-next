import Foundation

public enum AttachmentUploadPolicy {
    public enum Rejection: Sendable, Equatable {
        case permission, disabled, directMessage, count, size
    }

    public static func rejection(
        settings: SharkordSettings?, canSend: Bool, canUpload: Bool,
        isDM: Bool, fileCount: Int, fileSize: Int = 0
    ) -> Rejection? {
        guard canSend, canUpload else { return .permission }
        guard settings?.storageUploadEnabled == true else { return .disabled }
        if isDM, settings?.storageFileSharingInDirectMessages != true { return .directMessage }
        if let maximum = settings?.storageMaxFilesPerMessage, fileCount > maximum { return .count }
        if let maximum = settings?.storageUploadMaxFileSize, fileSize > maximum { return .size }
        return nil
    }
}
