/// Controls archive traversal after receiving a payload block.
public enum ArchiveDataBlockDisposition: Sendable, Equatable {
    /// Continue streaming the current entry.
    case continueReading
    /// Skip the current entry's remaining payload and continue with the next entry.
    case finishEntry
    /// Stop traversing the archive immediately.
    case stop
}
