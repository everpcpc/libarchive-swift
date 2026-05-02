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
    public let accessDate: Date?
    public let changeDate: Date?
    public let birthDate: Date?
    public let symlinkTarget: String?
    public let hardlinkTarget: String?
    public let uid: Int64?
    public let gid: Int64?
    public let userName: String?
    public let groupName: String?
    public let isDataEncrypted: Bool
    public let isMetadataEncrypted: Bool

    public init(
        path: String,
        size: Int64,
        fileType: FileType,
        permissions: UInt16,
        modificationDate: Date?,
        accessDate: Date? = nil,
        changeDate: Date? = nil,
        birthDate: Date? = nil,
        symlinkTarget: String? = nil,
        hardlinkTarget: String? = nil,
        uid: Int64? = nil,
        gid: Int64? = nil,
        userName: String? = nil,
        groupName: String? = nil,
        isDataEncrypted: Bool = false,
        isMetadataEncrypted: Bool = false
    ) {
        self.path = path
        self.size = size
        self.fileType = fileType
        self.permissions = permissions
        self.modificationDate = modificationDate
        self.accessDate = accessDate
        self.changeDate = changeDate
        self.birthDate = birthDate
        self.symlinkTarget = symlinkTarget
        self.hardlinkTarget = hardlinkTarget
        self.uid = uid
        self.gid = gid
        self.userName = userName
        self.groupName = groupName
        self.isDataEncrypted = isDataEncrypted
        self.isMetadataEncrypted = isMetadataEncrypted
    }
}
