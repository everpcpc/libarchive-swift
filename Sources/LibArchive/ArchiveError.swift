import Foundation

public enum ArchiveError: Error, Equatable, Sendable {
    case cannotCreateReader
    case cannotCreateWriter
    case cannotCreateDirectory(path: String, message: String)
    case cannotOpenArchive(path: String, message: String)
    case readFailed(message: String)
    case writeFailed(message: String)
    case invalidEntryPath
    case unsafeEntryPath(String)
    case unsafeLinkPath(entry: String, link: String)
}
