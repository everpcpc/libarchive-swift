import Foundation

public enum ArchiveError: Error, Equatable, Sendable {
    case cannotCreateReader
    case cannotCreateWriter
    case cannotCreateDirectory(path: String, message: String)
    case cannotOpenArchive(path: String, message: String)
    case entryNotFound(path: String)
    case entryDataTooLarge(path: String)
    case invalidEntryDataOffset(path: String, offset: Int64)
    case readFailed(message: String)
    case writeFailed(message: String)
    case cannotCreateUTF8Locale(candidates: [String])
    case invalidEntryPath
    case unsafeEntryPath(String)
    case unsafeLinkPath(entry: String, link: String)
}
