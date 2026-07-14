/// Controls whether an archive entry's payload should be streamed.
public enum ArchiveEntryDataSelection: Sendable, Equatable {
    /// Stream the entry's payload blocks to the receiver.
    case read
    /// Skip the entry's payload and continue traversing the archive.
    case skip
    /// Stop traversing the archive without reading the entry's payload.
    case stop
}
