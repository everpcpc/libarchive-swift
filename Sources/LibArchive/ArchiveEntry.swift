import Foundation

public struct ArchiveEntry: Sendable, Equatable {
    public enum FileType: Sendable, Equatable {
        case regular
        case directory
        case symbolicLink
        case hardLink
        case characterDevice
        case blockDevice
        case fifo
        case socket
        case unknown(Int)
    }

    public let path: String
    public let size: Int64
    public let fileType: FileType
    public let permissions: UInt16
    public let modificationDate: Date?

    public init(
        path: String,
        size: Int64,
        fileType: FileType,
        permissions: UInt16,
        modificationDate: Date?
    ) {
        self.path = path
        self.size = size
        self.fileType = fileType
        self.permissions = permissions
        self.modificationDate = modificationDate
    }
}
