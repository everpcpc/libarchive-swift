import Foundation

public enum ArchiveError: Error, Equatable, Sendable {
    case cannotCreateReader
    case cannotOpenArchive(path: String, message: String)
    case readFailed(message: String)
    case invalidEntryPath
}
