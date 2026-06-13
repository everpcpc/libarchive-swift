import Foundation

public enum ArchiveHeaderEncodingStrategy: Sendable, Equatable {
    case none
    case fixed(String.Encoding)
    case automatic([String.Encoding])
}

public struct ArchiveReadOptions: Sendable, Equatable {
    public var headerEncodingStrategy: ArchiveHeaderEncodingStrategy

    public init(headerEncodingStrategy: ArchiveHeaderEncodingStrategy = .none) {
        self.headerEncodingStrategy = headerEncodingStrategy
    }

    public static let `default` = ArchiveReadOptions()

    public static func headerEncoding(_ encoding: String.Encoding) -> ArchiveReadOptions {
        ArchiveReadOptions(headerEncodingStrategy: .fixed(encoding))
    }

    public static func automaticHeaderEncoding(candidates: [String.Encoding]) -> ArchiveReadOptions {
        ArchiveReadOptions(headerEncodingStrategy: .automatic(candidates))
    }
}
