import Foundation

public struct ArchiveDataBlock: Sendable, Equatable {
    public let offset: Int64
    public let data: Data

    public init(offset: Int64, data: Data) {
        self.offset = offset
        self.data = data
    }
}
