import CArchive
import Darwin
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
        try withOpenArchive(at: fileURL) { archive in
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

                result.append(Self.entry(from: entryPointer, path: String(cString: path)))

                let skipStatus = archive_read_data_skip(archive)
                guard skipStatus == ARCHIVE_OK || skipStatus == ARCHIVE_WARN else {
                    throw ArchiveError.readFailed(message: Self.errorMessage(from: archive))
                }
            }

            return result
        }
    }

    public func data(forEntryPath entryPath: String, in fileURL: URL) throws -> Data {
        var data = Data()

        try readDataBlocks(forEntryPath: entryPath, in: fileURL) { block in
            guard block.offset >= 0 else {
                throw ArchiveError.invalidEntryDataOffset(path: entryPath, offset: block.offset)
            }

            guard block.offset <= Int64(Int.max) else {
                throw ArchiveError.entryDataTooLarge(path: entryPath)
            }

            let offset = Int(block.offset)
            if data.count < offset {
                data.append(Data(repeating: 0, count: offset - data.count))
            }

            let endOffset = offset + block.data.count
            guard endOffset >= offset else {
                throw ArchiveError.entryDataTooLarge(path: entryPath)
            }

            if data.count < endOffset {
                data.append(Data(repeating: 0, count: endOffset - data.count))
            }

            data.replaceSubrange(offset..<endOffset, with: block.data)
        }

        return data
    }

    public func readDataBlocks(
        forEntryPath entryPath: String,
        in fileURL: URL,
        _ receive: (ArchiveDataBlock) throws -> Void
    ) throws {
        var foundEntry = false

        try withOpenArchive(at: fileURL) { archive in
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

                if String(cString: path) == entryPath {
                    foundEntry = true
                    try Self.readDataBlocks(from: archive, receive)
                    break
                }

                let skipStatus = archive_read_data_skip(archive)
                guard skipStatus == ARCHIVE_OK || skipStatus == ARCHIVE_WARN else {
                    throw ArchiveError.readFailed(message: Self.errorMessage(from: archive))
                }
            }
        }

        if !foundEntry {
            throw ArchiveError.entryNotFound(path: entryPath)
        }
    }

    public func extract(
        _ fileURL: URL,
        to destinationURL: URL,
        options: ArchiveExtractionOptions = .default
    ) throws {
        do {
            try FileManager.default.createDirectory(
                at: destinationURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw ArchiveError.cannotCreateDirectory(
                path: destinationURL.path,
                message: error.localizedDescription
            )
        }

        let extractionRootURL = try Self.resolvedDirectoryURL(destinationURL)

        try withOpenArchive(at: fileURL) { archive in
            guard let disk = archive_write_disk_new() else {
                throw ArchiveError.cannotCreateWriter
            }
            defer {
                archive_write_free(disk)
            }

            archive_write_disk_set_options(disk, options.diskFlags)
            archive_write_disk_set_standard_lookup(disk)

            var entryPointer: OpaquePointer?

            while true {
                let readStatus = archive_read_next_header(archive, &entryPointer)

                if readStatus == ARCHIVE_EOF {
                    break
                }

                guard readStatus == ARCHIVE_OK else {
                    throw ArchiveError.readFailed(message: Self.errorMessage(from: archive))
                }

                guard let entryPointer, let pathPointer = archive_entry_pathname(entryPointer) else {
                    throw ArchiveError.invalidEntryPath
                }

                let entryPath = String(cString: pathPointer)
                let outputURL = try Self.outputURL(
                    forEntryPath: entryPath,
                    relativeTo: extractionRootURL
                )

                try Self.validateLinkTargets(entry: entryPointer, entryPath: entryPath)

                try outputURL.withUnsafeFileSystemRepresentation { outputPath in
                    guard let outputPath else {
                        throw ArchiveError.invalidEntryPath
                    }

                    archive_entry_set_pathname(entryPointer, outputPath)
                }

                let writeHeaderStatus = archive_write_header(disk, entryPointer)
                guard writeHeaderStatus == ARCHIVE_OK || writeHeaderStatus == ARCHIVE_WARN else {
                    throw ArchiveError.writeFailed(message: Self.errorMessage(from: disk))
                }

                if archive_entry_size(entryPointer) > 0 {
                    try Self.copyData(from: archive, to: disk)
                }

                let finishStatus = archive_write_finish_entry(disk)
                guard finishStatus == ARCHIVE_OK || finishStatus == ARCHIVE_WARN else {
                    throw ArchiveError.writeFailed(message: Self.errorMessage(from: disk))
                }
            }

            let closeStatus = archive_write_close(disk)
            guard closeStatus == ARCHIVE_OK || closeStatus == ARCHIVE_WARN else {
                throw ArchiveError.writeFailed(message: Self.errorMessage(from: disk))
            }
        }
    }

    private static func entry(from entry: OpaquePointer, path: String) -> ArchiveEntry {
        ArchiveEntry(
            path: path,
            size: archive_entry_size(entry),
            fileType: fileType(from: entry),
            permissions: UInt16(archive_entry_perm(entry)),
            modificationDate: date(isSet: archive_entry_mtime_is_set(entry), seconds: archive_entry_mtime(entry)),
            accessDate: date(isSet: archive_entry_atime_is_set(entry), seconds: archive_entry_atime(entry)),
            changeDate: date(isSet: archive_entry_ctime_is_set(entry), seconds: archive_entry_ctime(entry)),
            birthDate: date(isSet: archive_entry_birthtime_is_set(entry), seconds: archive_entry_birthtime(entry)),
            symlinkTarget: string(from: archive_entry_symlink(entry)),
            hardlinkTarget: string(from: archive_entry_hardlink(entry)),
            uid: int64Value(isSet: archive_entry_uid_is_set(entry), value: archive_entry_uid(entry)),
            gid: int64Value(isSet: archive_entry_gid_is_set(entry), value: archive_entry_gid(entry)),
            userName: string(from: archive_entry_uname(entry)),
            groupName: string(from: archive_entry_gname(entry)),
            isDataEncrypted: archive_entry_is_data_encrypted(entry) != 0,
            isMetadataEncrypted: archive_entry_is_metadata_encrypted(entry) != 0
        )
    }

    private static func date(isSet: Int32, seconds: Int) -> Date? {
        guard isSet != 0 else {
            return nil
        }

        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private static func fileType(from entry: OpaquePointer) -> ArchiveEntry.FileType {
        if archive_entry_hardlink_is_set(entry) != 0 {
            return .hardLink
        }

        let rawValue = archive_entry_filetype(entry)

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

    private static func string(from pointer: UnsafePointer<CChar>?) -> String? {
        pointer.map { String(cString: $0) }
    }

    private static func int64Value(isSet: Int32, value: Int64) -> Int64? {
        guard isSet != 0 else {
            return nil
        }

        return value
    }

    private static func errorMessage(from archive: OpaquePointer) -> String {
        guard let message = archive_error_string(archive) else {
            return "Unknown libarchive error"
        }

        return String(cString: message)
    }

    private func withOpenArchive<T>(
        at fileURL: URL,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
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

            Self.configure(archive: archive)

            let openStatus = archive_read_open_filename(archive, pathPointer, 10240)
            guard openStatus == ARCHIVE_OK else {
                throw ArchiveError.cannotOpenArchive(
                    path: fileURL.path,
                    message: Self.errorMessage(from: archive)
                )
            }

            defer {
                archive_read_close(archive)
            }

            return try body(archive)
        }
    }

    private static func configure(archive: OpaquePointer) {
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
    }

    private static func copyData(from archive: OpaquePointer, to disk: OpaquePointer) throws {
        try readDataBlocks(from: archive) { block in
            let writeStatus = block.data.withUnsafeBytes { buffer in
                archive_write_data_block(disk, buffer.baseAddress, block.data.count, block.offset)
            }
            guard writeStatus == ARCHIVE_OK else {
                throw ArchiveError.writeFailed(message: errorMessage(from: disk))
            }
        }
    }

    private static func readDataBlocks(
        from archive: OpaquePointer,
        _ receive: (ArchiveDataBlock) throws -> Void
    ) throws {
        while true {
            var buffer: UnsafeRawPointer?
            var size = 0
            var offset: Int64 = 0
            let readStatus = archive_read_data_block(archive, &buffer, &size, &offset)

            if readStatus == ARCHIVE_EOF {
                break
            }

            guard readStatus == ARCHIVE_OK else {
                throw ArchiveError.readFailed(message: errorMessage(from: archive))
            }

            guard let buffer else {
                continue
            }

            try receive(ArchiveDataBlock(offset: offset, data: Data(bytes: buffer, count: size)))
        }
    }

    private static func outputURL(forEntryPath entryPath: String, relativeTo destinationURL: URL) throws -> URL {
        guard !entryPath.isEmpty, !entryPath.hasPrefix("/") else {
            throw ArchiveError.unsafeEntryPath(entryPath)
        }

        let components = entryPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        if components.contains("..") {
            throw ArchiveError.unsafeEntryPath(entryPath)
        }

        let outputURL = components.reduce(destinationURL) { partialURL, component in
            component == "." ? partialURL : partialURL.appendingPathComponent(component)
        }

        let destinationPath = destinationURL.path
        let outputPath = outputURL.path

        guard outputPath == destinationPath || outputPath.hasPrefix(destinationPath + "/") else {
            throw ArchiveError.unsafeEntryPath(entryPath)
        }

        return outputURL
    }

    private static func validateLinkTargets(entry: OpaquePointer, entryPath: String) throws {
        if let symlink = archive_entry_symlink(entry) {
            let linkPath = String(cString: symlink)
            try validateRelativeLinkPath(linkPath, entryPath: entryPath)
        }

        if let hardlink = archive_entry_hardlink(entry) {
            let linkPath = String(cString: hardlink)
            try validateRelativeLinkPath(linkPath, entryPath: entryPath)
        }
    }

    private static func validateRelativeLinkPath(_ linkPath: String, entryPath: String) throws {
        guard !linkPath.hasPrefix("/") else {
            throw ArchiveError.unsafeLinkPath(entry: entryPath, link: linkPath)
        }

        let hasParentTraversal = linkPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .contains("..")

        if hasParentTraversal {
            throw ArchiveError.unsafeLinkPath(entry: entryPath, link: linkPath)
        }
    }

    private static func resolvedDirectoryURL(_ directoryURL: URL) throws -> URL {
        try directoryURL.withUnsafeFileSystemRepresentation { pathPointer in
            guard let pathPointer, let resolvedPath = realpath(pathPointer, nil) else {
                throw ArchiveError.cannotCreateDirectory(
                    path: directoryURL.path,
                    message: "Unable to resolve destination path"
                )
            }
            defer {
                free(resolvedPath)
            }

            return URL(fileURLWithPath: String(cString: resolvedPath), isDirectory: true)
        }
    }
}
