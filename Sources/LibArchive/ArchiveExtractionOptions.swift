import CArchive

public struct ArchiveExtractionOptions: OptionSet, Sendable {
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public static let preserveOwner = Self(rawValue: Int32(ARCHIVE_EXTRACT_OWNER))
    public static let preservePermissions = Self(rawValue: Int32(ARCHIVE_EXTRACT_PERM))
    public static let preserveModificationTime = Self(rawValue: Int32(ARCHIVE_EXTRACT_TIME))
    public static let noOverwrite = Self(rawValue: Int32(ARCHIVE_EXTRACT_NO_OVERWRITE))
    public static let noOverwriteNewer = Self(rawValue: Int32(ARCHIVE_EXTRACT_NO_OVERWRITE_NEWER))
    public static let unlinkExisting = Self(rawValue: Int32(ARCHIVE_EXTRACT_UNLINK))
    public static let preserveACL = Self(rawValue: Int32(ARCHIVE_EXTRACT_ACL))
    public static let preserveFileFlags = Self(rawValue: Int32(ARCHIVE_EXTRACT_FFLAGS))
    public static let preserveExtendedAttributes = Self(rawValue: Int32(ARCHIVE_EXTRACT_XATTR))
    public static let sparse = Self(rawValue: Int32(ARCHIVE_EXTRACT_SPARSE))
    public static let safeWrites = Self(rawValue: Int32(ARCHIVE_EXTRACT_SAFE_WRITES))

    public static let `default`: Self = [
        .preserveModificationTime,
        .safeWrites,
    ]

    var diskFlags: Int32 {
        rawValue
            | Int32(ARCHIVE_EXTRACT_SECURE_SYMLINKS)
            | Int32(ARCHIVE_EXTRACT_SECURE_NODOTDOT)
    }
}
