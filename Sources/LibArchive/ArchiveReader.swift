import CArchive
import Foundation

public enum LibArchive {
    public static var versionString: String {
        String(cString: archive_version_string())
    }

    public static var versionNumber: Int {
        Int(archive_version_number())
    }
}

public final class ArchiveReader {
    private static let fileTypeMask = mode_t(0o170000)
    private static let regularFile = mode_t(0o100000)
    private static let directory = mode_t(0o040000)
    private static let symbolicLink = mode_t(0o120000)
    private static let characterDevice = mode_t(0o020000)
    private static let blockDevice = mode_t(0o060000)
    private static let fifo = mode_t(0o010000)
    private static let socket = mode_t(0o140000)

    public init() {}

    public func entries(at fileURL: URL) throws -> [ArchiveEntry] {
        try fileURL.withUnsafeFileSystemRepresentation { pathPointer in
            guard let pathPointer else {
                throw ArchiveError.cannotOpenArchive(path: fileURL.path, message: "Invalid file system path")
            }

            guard let archive = archive_read_new() else {
                throw ArchiveError.cannotCreateReader
            }
            defer {
                archive_read_free(archive)
            }

            archive_read_support_filter_none(archive)
            archive_read_support_filter_gzip(archive)
            archive_read_support_filter_compress(archive)
            archive_read_support_filter_uu(archive)
            archive_read_support_filter_rpm(archive)
            archive_read_support_format_7zip(archive)
            archive_read_support_format_ar(archive)
            archive_read_support_format_cab(archive)
            archive_read_support_format_cpio(archive)
            archive_read_support_format_empty(archive)
            archive_read_support_format_iso9660(archive)
            archive_read_support_format_lha(archive)
            archive_read_support_format_mtree(archive)
            archive_read_support_format_rar(archive)
            archive_read_support_format_rar5(archive)
            archive_read_support_format_tar(archive)
            archive_read_support_format_warc(archive)
            archive_read_support_format_zip(archive)

            let openStatus = archive_read_open_filename(archive, pathPointer, 10240)
            guard openStatus == ARCHIVE_OK else {
                throw ArchiveError.cannotOpenArchive(
                    path: fileURL.path,
                    message: Self.errorMessage(from: archive)
                )
            }

            var result: [ArchiveEntry] = []
            var entryPointer: OpaquePointer?

            while true {
                let status = archive_read_next_header(archive, &entryPointer)

                if status == ARCHIVE_EOF {
                    break
                }

                guard status == ARCHIVE_OK else {
                    throw ArchiveError.readFailed(message: Self.errorMessage(from: archive))
                }

                guard let entryPointer, let path = archive_entry_pathname(entryPointer) else {
                    throw ArchiveError.invalidEntryPath
                }

                result.append(
                    ArchiveEntry(
                        path: String(cString: path),
                        size: archive_entry_size(entryPointer),
                        fileType: Self.fileType(from: archive_entry_filetype(entryPointer)),
                        permissions: UInt16(archive_entry_perm(entryPointer)),
                        modificationDate: Self.modificationDate(from: entryPointer)
                    )
                )

                let skipStatus = archive_read_data_skip(archive)
                guard skipStatus == ARCHIVE_OK || skipStatus == ARCHIVE_WARN else {
                    throw ArchiveError.readFailed(message: Self.errorMessage(from: archive))
                }
            }

            return result
        }
    }

    private static func modificationDate(from entry: OpaquePointer) -> Date? {
        guard archive_entry_mtime_is_set(entry) != 0 else {
            return nil
        }

        return Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry)))
    }

    private static func fileType(from rawValue: mode_t) -> ArchiveEntry.FileType {
        switch rawValue & fileTypeMask {
        case regularFile:
            return .regular
        case directory:
            return .directory
        case symbolicLink:
            return .symbolicLink
        case characterDevice:
            return .characterDevice
        case blockDevice:
            return .blockDevice
        case fifo:
            return .fifo
        case socket:
            return .socket
        default:
            return .unknown(Int(rawValue))
        }
    }

    private static func errorMessage(from archive: OpaquePointer) -> String {
        guard let message = archive_error_string(archive) else {
            return "Unknown libarchive error"
        }

        return String(cString: message)
    }
}
