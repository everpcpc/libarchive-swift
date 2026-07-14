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

    private let readOptions: ArchiveReadOptions

    public init(readOptions: ArchiveReadOptions = .default) {
        self.readOptions = readOptions
    }

    public func entries(at fileURL: URL) throws -> [ArchiveEntry] {
        try withOpenArchive(at: fileURL) { archive in
            var result: [ArchiveEntry] = []
            var entryPointer: OpaquePointer?

            while true {
                let status = archive_read_next_header(archive, &entryPointer)

                if status == ARCHIVE_EOF {
                    break
                }

                guard status == ARCHIVE_OK || status == ARCHIVE_WARN else {
                    throw ArchiveError.readFailed(message: Self.errorMessage(from: archive))
                }

                guard let entryPointer else {
                    throw ArchiveError.invalidEntryPath
                }
                let path = try Self.path(from: entryPointer, readOptions: readOptions)

                result.append(Self.entry(from: entryPointer, path: path, readOptions: readOptions))

                try Self.skipEntryData(from: archive)
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

                guard status == ARCHIVE_OK || status == ARCHIVE_WARN else {
                    throw ArchiveError.readFailed(message: Self.errorMessage(from: archive))
                }

                guard let entryPointer else {
                    throw ArchiveError.invalidEntryPath
                }
                let path = try Self.path(from: entryPointer, readOptions: readOptions)

                if path == entryPath {
                    foundEntry = true
                    try Self.readDataBlocks(from: archive, receive)
                    break
                }

                try Self.skipEntryData(from: archive)
            }
        }

        if !foundEntry {
            throw ArchiveError.entryNotFound(path: entryPath)
        }
    }

    /// Streams selected entry payloads while traversing the archive once.
    ///
    /// The selection closure runs for each entry before its payload is read. The receiver can
    /// finish the current entry early or stop the entire traversal after inspecting a block.
    /// `didFinishEntry` runs only for selected entries that reach EOF or are finished early.
    public func readDataBlocks(
        in fileURL: URL,
        selecting selection: (ArchiveEntry) throws -> ArchiveEntryDataSelection,
        didFinishEntry: (
            _ entry: ArchiveEntry,
            _ consumedToEOF: Bool
        ) throws -> Void = { _, _ in },
        _ receive: (
            _ entry: ArchiveEntry,
            _ block: ArchiveDataBlock
        ) throws -> ArchiveDataBlockDisposition
    ) throws {
        try withOpenArchive(at: fileURL) { archive in
            var entryPointer: OpaquePointer?

            archiveLoop: while true {
                let headerStatus = archive_read_next_header(archive, &entryPointer)

                if headerStatus == ARCHIVE_EOF {
                    break
                }

                guard headerStatus == ARCHIVE_OK || headerStatus == ARCHIVE_WARN else {
                    throw ArchiveError.readFailed(message: Self.errorMessage(from: archive))
                }

                guard let entryPointer else {
                    throw ArchiveError.invalidEntryPath
                }

                let path = try Self.path(from: entryPointer, readOptions: readOptions)
                let entry = Self.entry(from: entryPointer, path: path, readOptions: readOptions)

                switch try selection(entry) {
                case .read:
                    break
                case .skip:
                    try Self.skipEntryData(from: archive)
                    continue
                case .stop:
                    break archiveLoop
                }

                while true {
                    switch try Self.nextDataBlock(from: archive) {
                    case .block(let block):
                        switch try receive(entry, block) {
                        case .continueReading:
                            continue
                        case .finishEntry:
                            try Self.skipEntryData(from: archive)
                            try didFinishEntry(entry, false)
                            continue archiveLoop
                        case .stop:
                            break archiveLoop
                        }
                    case .end:
                        try didFinishEntry(entry, true)
                        continue archiveLoop
                    }
                }
            }
        }
    }

    public func extract(
        _ fileURL: URL,
        to destinationURL: URL,
        options: ArchiveExtractionOptions = .default,
        permissionMode: ArchiveExtractionPermissionMode = .archive
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

                guard readStatus == ARCHIVE_OK || readStatus == ARCHIVE_WARN else {
                    throw ArchiveError.readFailed(message: Self.errorMessage(from: archive))
                }

                guard let entryPointer else {
                    throw ArchiveError.invalidEntryPath
                }

                let entryPath = try Self.path(from: entryPointer, readOptions: readOptions)
                let outputURL = try Self.outputURL(
                    forEntryPath: entryPath,
                    relativeTo: extractionRootURL
                )

                try Self.validateLinkTargets(entry: entryPointer, entryPath: entryPath, readOptions: readOptions)

                try outputURL.withUnsafeFileSystemRepresentation { outputPath in
                    guard let outputPath else {
                        throw ArchiveError.invalidEntryPath
                    }

                    archive_entry_set_pathname(entryPointer, outputPath)
                }

                Self.normalizePermissionsIfNeeded(for: entryPointer, permissionMode: permissionMode)

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

    private static func normalizePermissionsIfNeeded(
        for entry: OpaquePointer,
        permissionMode: ArchiveExtractionPermissionMode
    ) {
        let filePermission: UInt16
        let directoryPermission: UInt16

        switch permissionMode {
        case .archive:
            return
        case .normalized:
            filePermission = 0o644
            directoryPermission = 0o755
        case let .custom(file, directory):
            filePermission = file
            directoryPermission = directory
        }

        switch fileType(from: entry) {
        case .regular:
            archive_entry_set_perm(entry, mode_t(filePermission))
        case .directory:
            archive_entry_set_perm(entry, mode_t(directoryPermission))
        default:
            break
        }
    }

    private static func entry(from entry: OpaquePointer, path: String, readOptions: ArchiveReadOptions) -> ArchiveEntry {
        ArchiveEntry(
            path: path,
            size: archive_entry_size(entry),
            fileType: fileType(from: entry),
            permissions: UInt16(archive_entry_perm(entry)),
            modificationDate: date(isSet: archive_entry_mtime_is_set(entry), seconds: archive_entry_mtime(entry)),
            accessDate: date(isSet: archive_entry_atime_is_set(entry), seconds: archive_entry_atime(entry)),
            changeDate: date(isSet: archive_entry_ctime_is_set(entry), seconds: archive_entry_ctime(entry)),
            birthDate: date(isSet: archive_entry_birthtime_is_set(entry), seconds: archive_entry_birthtime(entry)),
            symlinkTarget: linkTarget(from: entry, utf8: archive_entry_symlink_utf8, fallback: archive_entry_symlink, readOptions: readOptions),
            hardlinkTarget: linkTarget(from: entry, utf8: archive_entry_hardlink_utf8, fallback: archive_entry_hardlink, readOptions: readOptions),
            uid: int64Value(isSet: archive_entry_uid_is_set(entry), value: archive_entry_uid(entry)),
            gid: int64Value(isSet: archive_entry_gid_is_set(entry), value: archive_entry_gid(entry)),
            userName: utf8String(from: archive_entry_uname_utf8(entry), fallback: archive_entry_uname(entry), readOptions: readOptions),
            groupName: utf8String(from: archive_entry_gname_utf8(entry), fallback: archive_entry_gname(entry), readOptions: readOptions),
            isDataEncrypted: archive_entry_is_data_encrypted(entry) != 0,
            isMetadataEncrypted: archive_entry_is_metadata_encrypted(entry) != 0
        )
    }

    private static func path(from entry: OpaquePointer, readOptions: ArchiveReadOptions) throws -> String {
        if let path = utf8String(
            from: archive_entry_pathname_utf8(entry),
            fallback: archive_entry_pathname(entry),
            readOptions: readOptions
        ) {
            return path
        }

        throw ArchiveError.invalidEntryPath
    }

    private static func utf8String(
        from utf8Pointer: UnsafePointer<CChar>?,
        fallback: UnsafePointer<CChar>?,
        readOptions: ArchiveReadOptions
    ) -> String? {
        switch readOptions.headerEncodingStrategy {
        case .fixed:
            if let fallback {
                return decodeFallbackString(from: fallback, readOptions: readOptions)
            }
        case .none, .automatic:
            break
        }

        if let utf8Pointer {
            return String(cString: utf8Pointer)
        }

        if let fallback {
            return decodeFallbackString(from: fallback, readOptions: readOptions)
        }

        return nil
    }

    private static func decodeFallbackString(
        from pointer: UnsafePointer<CChar>,
        readOptions: ArchiveReadOptions
    ) -> String {
        let byteCount = strlen(pointer)
        let data = Data(bytes: pointer, count: byteCount)

        switch readOptions.headerEncodingStrategy {
        case .none:
            return String(cString: pointer)
        case let .fixed(encoding):
            return Self.string(from: data, encoding: encoding) ?? String(cString: pointer)
        case let .automatic(candidates):
            return Self.bestString(from: data, candidates: candidates) ?? String(cString: pointer)
        }
    }

    private static func string(from data: Data, encoding: String.Encoding) -> String? {
        guard let string = String(data: data, encoding: encoding) else {
            return nil
        }

        guard string.data(using: encoding) == data else {
            return nil
        }

        return string
    }

    private static func bestString(from data: Data, candidates: [String.Encoding]) -> String? {
        var bestCandidate: (string: String, score: Int)?

        for candidate in candidates {
            guard let string = string(from: data, encoding: candidate) else {
                continue
            }

            let score = stringScore(string)
            if bestCandidate == nil || score > bestCandidate!.score {
                bestCandidate = (string, score)
            }
        }

        return bestCandidate?.string
    }

    private static func stringScore(_ string: String) -> Int {
        var score = 0

        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x20...0x7E:
                score += 1
            case 0x3040...0x30FF:
                score += 8
            case 0x4E00...0x9FFF, 0x3400...0x4DBF:
                score += 4
            case 0xFF61...0xFF9F:
                score += 2
            case 0x3000...0x303F, 0xFF00...0xFFEF:
                score += 2
            case 0x0000...0x001F, 0x007F...0x009F:
                score -= 20
            case 0xE000...0xF8FF:
                score -= 5
            default:
                score += 1
            }
        }

        return score
    }

    private static func linkTarget(
        from entry: OpaquePointer,
        utf8: (OpaquePointer) -> UnsafePointer<CChar>?,
        fallback: (OpaquePointer) -> UnsafePointer<CChar>?,
        readOptions: ArchiveReadOptions
    ) -> String? {
        utf8String(from: utf8(entry), fallback: fallback(entry), readOptions: readOptions)
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

    private static let utf8LocaleCandidates = ["C.UTF-8", "UTF-8", "en_US.UTF-8", "en_US.UTF8"]

    private static func withUTF8Locale<T>(_ body: () throws -> T) throws -> T {
        let locale = utf8LocaleCandidates.lazy.compactMap { candidate in
            newlocale(LC_CTYPE_MASK, candidate, nil)
        }.first

        guard let locale else {
            throw ArchiveError.cannotCreateUTF8Locale(candidates: utf8LocaleCandidates)
        }
        defer {
            freelocale(locale)
        }

        let previousLocale = uselocale(locale)
        defer {
            uselocale(previousLocale)
        }

        return try body()
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

            return try Self.withUTF8Locale {
                try body(archive)
            }
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
            switch try nextDataBlock(from: archive) {
            case .block(let block):
                try receive(block)
            case .end:
                return
            }
        }
    }

    private enum DataBlockReadResult {
        case block(ArchiveDataBlock)
        case end
    }

    private static func nextDataBlock(from archive: OpaquePointer) throws -> DataBlockReadResult {
        while true {
            var buffer: UnsafeRawPointer?
            var size = 0
            var offset: Int64 = 0
            let readStatus = archive_read_data_block(archive, &buffer, &size, &offset)

            if readStatus == ARCHIVE_EOF {
                return .end
            }

            guard readStatus == ARCHIVE_OK else {
                throw ArchiveError.readFailed(message: errorMessage(from: archive))
            }

            guard let buffer else {
                continue
            }

            return .block(
                ArchiveDataBlock(offset: offset, data: Data(bytes: buffer, count: size))
            )
        }
    }

    private static func skipEntryData(from archive: OpaquePointer) throws {
        let skipStatus = archive_read_data_skip(archive)
        guard skipStatus == ARCHIVE_OK || skipStatus == ARCHIVE_WARN else {
            throw ArchiveError.readFailed(message: errorMessage(from: archive))
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

    private static func validateLinkTargets(entry: OpaquePointer, entryPath: String, readOptions: ArchiveReadOptions) throws {
        if let symlink = linkTarget(from: entry, utf8: archive_entry_symlink_utf8, fallback: archive_entry_symlink, readOptions: readOptions) {
            try validateRelativeLinkPath(symlink, entryPath: entryPath)
        }

        if let hardlink = linkTarget(from: entry, utf8: archive_entry_hardlink_utf8, fallback: archive_entry_hardlink, readOptions: readOptions) {
            try validateRelativeLinkPath(hardlink, entryPath: entryPath)
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
