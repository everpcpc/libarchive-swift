import Darwin
import Foundation
import LibArchive
import Testing

@Test
func listsEntriesFromTarArchive() throws {
    let workspace = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceDirectory = workspace.appendingPathComponent("source", isDirectory: true)
    let archiveURL = workspace.appendingPathComponent("sample.tar")

    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    try "hello\n".write(
        to: sourceDirectory.appendingPathComponent("hello.txt"),
        atomically: true,
        encoding: .utf8
    )

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.arguments = ["-cf", archiveURL.path, "-C", sourceDirectory.path, "."]
    try process.run()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)

    let entries = try ArchiveReader().entries(at: archiveURL)
    #expect(entries.contains { $0.path == "./hello.txt" || $0.path == "hello.txt" })
}

@Test
func listsEntriesFromZipArchive() throws {
    let workspace = try makeWorkspace()
    let sourceDirectory = workspace.appendingPathComponent("source", isDirectory: true)
    let archiveURL = workspace.appendingPathComponent("sample.zip")

    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    try "hello\n".write(
        to: sourceDirectory.appendingPathComponent("hello.txt"),
        atomically: true,
        encoding: .utf8
    )

    try run("/usr/bin/zip", arguments: ["-qr", archiveURL.path, "hello.txt"], currentDirectory: sourceDirectory)

    let entries = try ArchiveReader().entries(at: archiveURL)
    #expect(entries.contains { $0.path == "hello.txt" })
}

@Test
func listsEntriesFromRarArchive() throws {
    let archiveURL = try fixtureURL(named: "test_read_format_rar.rar")
    let entries = try ArchiveReader().entries(at: archiveURL)
    #expect(entries.contains { $0.path == "test.txt" })
}

@Test
func listsEntriesFromRar5Archive() throws {
    let archiveURL = try fixtureURL(named: "test_read_format_rar5_stored.rar")
    let entries = try ArchiveReader().entries(at: archiveURL)
    #expect(entries.contains { $0.path == "helloworld.txt" })
}

@Test
func readsEntryDataFromTarArchive() throws {
    let workspace = try makeWorkspace()
    let archiveURL = workspace.appendingPathComponent("sample.tar")

    try writeTarArchive(
        entries: [
            .regular(path: "folder/hello.txt", contents: Data("hello\n".utf8)),
        ],
        to: archiveURL
    )

    let data = try ArchiveReader().data(forEntryPath: "folder/hello.txt", in: archiveURL)
    #expect(String(decoding: data, as: UTF8.self) == "hello\n")
}

@Test
func streamsEntryDataBlocksFromTarArchive() throws {
    let workspace = try makeWorkspace()
    let archiveURL = workspace.appendingPathComponent("sample.tar")

    try writeTarArchive(
        entries: [
            .regular(path: "hello.txt", contents: Data("hello\n".utf8)),
        ],
        to: archiveURL
    )

    var blocks: [ArchiveDataBlock] = []
    try ArchiveReader().readDataBlocks(forEntryPath: "hello.txt", in: archiveURL) { block in
        blocks.append(block)
    }

    #expect(blocks.map(\.offset) == [0])
    #expect(String(decoding: blocks.flatMap(\.data), as: UTF8.self) == "hello\n")
}

@Test
func streamsSelectedEntryDataBlocksInSingleArchivePass() throws {
    let workspace = try makeWorkspace()
    let archiveURL = workspace.appendingPathComponent("sample.tar")

    try writeTarArchive(
        entries: [
            .regular(path: "skip.txt", contents: Data("skip\n".utf8)),
            .regular(path: "first.txt", contents: Data("first\n".utf8)),
            .regular(path: "second.txt", contents: Data("second\n".utf8)),
        ],
        to: archiveURL
    )

    let selectedPaths: Set<String> = ["first.txt", "second.txt"]
    var visitedPaths: [String] = []
    var receivedData: [String: Data] = [:]
    var completions: [(path: String, consumedToEOF: Bool)] = []

    try ArchiveReader().readDataBlocks(
        in: archiveURL,
        selecting: { entry in
            visitedPaths.append(entry.path)
            return selectedPaths.contains(entry.path) ? .read : .skip
        },
        didFinishEntry: { entry, consumedToEOF in
            completions.append((entry.path, consumedToEOF))
        }
    ) { entry, block in
        receivedData[entry.path, default: Data()].append(block.data)
        return .continueReading
    }

    #expect(visitedPaths == ["skip.txt", "first.txt", "second.txt"])
    #expect(String(decoding: receivedData["first.txt", default: Data()], as: UTF8.self) == "first\n")
    #expect(String(decoding: receivedData["second.txt", default: Data()], as: UTF8.self) == "second\n")
    #expect(completions.map { $0.path } == ["first.txt", "second.txt"])
    #expect(completions.allSatisfy { $0.consumedToEOF })
}

@Test
func finishesCurrentEntryEarlyAndStopsArchiveTraversal() throws {
    let workspace = try makeWorkspace()
    let archiveURL = workspace.appendingPathComponent("sample.tar")
    let largeContents = Data(repeating: 0x41, count: 1_000_000)

    try writeTarArchive(
        entries: [
            .regular(path: "partial.bin", contents: largeContents),
            .regular(path: "complete.txt", contents: Data("complete\n".utf8)),
            .regular(path: "stop.txt", contents: Data("stop\n".utf8)),
            .regular(path: "unvisited.txt", contents: Data("unvisited\n".utf8)),
        ],
        to: archiveURL
    )

    var visitedPaths: [String] = []
    var partialBlockCount = 0
    var completeData = Data()
    var completions: [(path: String, consumedToEOF: Bool)] = []

    try ArchiveReader().readDataBlocks(
        in: archiveURL,
        selecting: { entry in
            visitedPaths.append(entry.path)
            return entry.path == "stop.txt" ? .stop : .read
        },
        didFinishEntry: { entry, consumedToEOF in
            completions.append((entry.path, consumedToEOF))
        }
    ) { entry, block in
        if entry.path == "partial.bin" {
            partialBlockCount += 1
            return .finishEntry
        }

        completeData.append(block.data)
        return .continueReading
    }

    #expect(visitedPaths == ["partial.bin", "complete.txt", "stop.txt"])
    #expect(partialBlockCount == 1)
    #expect(String(decoding: completeData, as: UTF8.self) == "complete\n")
    #expect(completions.map { $0.path } == ["partial.bin", "complete.txt"])
    #expect(completions.map { $0.consumedToEOF } == [false, true])
}

@Test
func propagatesSelectedEntryReceiverErrors() throws {
    let workspace = try makeWorkspace()
    let archiveURL = workspace.appendingPathComponent("sample.tar")

    try writeTarArchive(
        entries: [
            .regular(path: "hello.txt", contents: Data("hello\n".utf8)),
        ],
        to: archiveURL
    )

    var didThrow = false

    do {
        try ArchiveReader().readDataBlocks(
            in: archiveURL,
            selecting: { _ in .read }
        ) { _, _ in
            throw ArchiveStreamingTestError.expected
        }
    } catch ArchiveStreamingTestError.expected {
        didThrow = true
    }

    #expect(didThrow)
}

@Test
func throwsWhenReadingMissingEntryData() throws {
    let workspace = try makeWorkspace()
    let archiveURL = workspace.appendingPathComponent("sample.tar")

    try writeTarArchive(
        entries: [
            .regular(path: "hello.txt", contents: Data("hello\n".utf8)),
        ],
        to: archiveURL
    )

    var didThrow = false

    do {
        _ = try ArchiveReader().data(forEntryPath: "missing.txt", in: archiveURL)
    } catch ArchiveError.entryNotFound("missing.txt") {
        didThrow = true
    }

    #expect(didThrow)
}

@Test
func exposesExtendedEntryMetadata() throws {
    let workspace = try makeWorkspace()
    let archiveURL = workspace.appendingPathComponent("sample.tar")

    try writeTarArchive(
        entries: [
            .regular(
                path: "hello.txt",
                contents: Data("hello\n".utf8),
                uid: 501,
                gid: 20,
                userName: "ever",
                groupName: "staff"
            ),
            .symlink(path: "hello-link.txt", target: "hello.txt"),
        ],
        to: archiveURL
    )

    let entries = try ArchiveReader().entries(at: archiveURL)
    let file = try #require(entries.first { $0.path == "hello.txt" })
    let link = try #require(entries.first { $0.path == "hello-link.txt" })

    #expect(file.uid == 501)
    #expect(file.gid == 20)
    #expect(file.userName == "ever")
    #expect(file.groupName == "staff")
    #expect(file.isDataEncrypted == false)
    #expect(file.isMetadataEncrypted == false)
    #expect(link.fileType == .symbolicLink)
    #expect(link.symlinkTarget == "hello.txt")
}

@Test
func extractsTarArchive() throws {
    let workspace = try makeWorkspace()
    let archiveURL = workspace.appendingPathComponent("sample.tar")
    let destinationURL = workspace.appendingPathComponent("output", isDirectory: true)

    try writeTarArchive(
        entries: [
            .regular(path: "folder/hello.txt", contents: Data("hello\n".utf8)),
        ],
        to: archiveURL
    )

    try ArchiveReader().extract(archiveURL, to: destinationURL)

    let extracted = try String(
        contentsOf: destinationURL.appendingPathComponent("folder/hello.txt"),
        encoding: .utf8
    )
    #expect(extracted == "hello\n")
}

@Test
func extractsArchiveWithNormalizedPermissions() throws {
    let workspace = try makeWorkspace()
    let archiveURL = workspace.appendingPathComponent("sample.tar")
    let destinationURL = workspace.appendingPathComponent("output", isDirectory: true)

    try writeTarArchive(
        entries: [
            .directory(path: "readonly", permissions: 0o555),
            .regular(path: "readonly/hello.txt", contents: Data("hello\n".utf8), permissions: 0o444),
        ],
        to: archiveURL
    )

    try ArchiveReader().extract(
        archiveURL,
        to: destinationURL,
        options: [.preservePermissions],
        permissionMode: .normalized
    )

    let directoryPermissions = try posixPermissions(
        at: destinationURL.appendingPathComponent("readonly", isDirectory: true)
    )
    let filePermissions = try posixPermissions(
        at: destinationURL.appendingPathComponent("readonly/hello.txt")
    )

    #expect(directoryPermissions == 0o755)
    #expect(filePermissions == 0o644)
}

@Test
func extractsZipArchive() throws {
    let workspace = try makeWorkspace()
    let sourceDirectory = workspace.appendingPathComponent("source", isDirectory: true)
    let archiveURL = workspace.appendingPathComponent("sample.zip")
    let destinationURL = workspace.appendingPathComponent("output", isDirectory: true)

    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    try "hello\n".write(
        to: sourceDirectory.appendingPathComponent("hello.txt"),
        atomically: true,
        encoding: .utf8
    )

    try run("/usr/bin/zip", arguments: ["-qr", archiveURL.path, "hello.txt"], currentDirectory: sourceDirectory)
    try ArchiveReader().extract(archiveURL, to: destinationURL)

    let extracted = try String(
        contentsOf: destinationURL.appendingPathComponent("hello.txt"),
        encoding: .utf8
    )
    #expect(extracted == "hello\n")
}

@Test
func extractsZipArchiveWithUTF8PathnamesInCLocale() throws {
    let workspace = try makeWorkspace()
    let sourceDirectory = workspace.appendingPathComponent("source", isDirectory: true)
    let archiveURL = workspace.appendingPathComponent("unicode.zip")
    let destinationURL = workspace.appendingPathComponent("output", isDirectory: true)
    let entryPath = "unicode/日本語-中文-한글/ページ-001.png"
    let imageURL = sourceDirectory.appendingPathComponent(entryPath)

    try FileManager.default.createDirectory(
        at: imageURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
    try run("/usr/bin/zip", arguments: ["-qr", archiveURL.path, entryPath], currentDirectory: sourceDirectory)

    let previousLocale = setlocale(LC_CTYPE, nil).map { String(cString: $0) }
    _ = setlocale(LC_CTYPE, "C")
    defer {
        if let previousLocale {
            setlocale(LC_CTYPE, previousLocale)
        }
    }

    let entries = try ArchiveReader().entries(at: archiveURL)
    #expect(entries.contains { $0.path == entryPath })

    try ArchiveReader().extract(archiveURL, to: destinationURL)
    #expect(FileManager.default.fileExists(atPath: destinationURL.appendingPathComponent(entryPath).path))
}

@Test
func listsAndExtractsZipArchiveWithShiftJISPathnames() throws {
    let workspace = try makeWorkspace()
    let archiveURL = workspace.appendingPathComponent("shift-jis.zip")
    let destinationURL = workspace.appendingPathComponent("output", isDirectory: true)
    let entryPath = "日本語/ページ.txt"
    let contents = Data("shift-jis\n".utf8)

    try writeStoredZipArchive(
        entries: [
            ZipEntry(
                pathBytes: try encodedPathBytes(entryPath, encoding: shiftJISEncoding),
                contents: contents
            ),
        ],
        to: archiveURL
    )

    let explicitReader = ArchiveReader(readOptions: .headerEncoding(shiftJISEncoding))
    let explicitEntries = try explicitReader.entries(at: archiveURL)
    #expect(explicitEntries.contains { $0.path == entryPath })
    #expect(try explicitReader.data(forEntryPath: entryPath, in: archiveURL) == contents)

    let automaticReader = ArchiveReader(
        readOptions: .automaticHeaderEncoding(candidates: legacyEncodingCandidates)
    )
    let automaticEntries = try automaticReader.entries(at: archiveURL)
    #expect(automaticEntries.contains { $0.path == entryPath })

    try explicitReader.extract(archiveURL, to: destinationURL)
    #expect(FileManager.default.fileExists(atPath: destinationURL.appendingPathComponent(entryPath).path))
}

@Test
func listsAndExtractsZipArchiveWithGBKPathnames() throws {
    let workspace = try makeWorkspace()
    let archiveURL = workspace.appendingPathComponent("gbk.zip")
    let destinationURL = workspace.appendingPathComponent("output", isDirectory: true)
    let entryPath = "简体中文/页面.txt"
    let contents = Data("gbk\n".utf8)

    try writeStoredZipArchive(
        entries: [
            ZipEntry(
                pathBytes: try encodedPathBytes(entryPath, encoding: gbkEncoding),
                contents: contents
            ),
        ],
        to: archiveURL
    )

    let explicitReader = ArchiveReader(readOptions: .headerEncoding(gbkEncoding))
    let explicitEntries = try explicitReader.entries(at: archiveURL)
    #expect(explicitEntries.contains { $0.path == entryPath })
    #expect(try explicitReader.data(forEntryPath: entryPath, in: archiveURL) == contents)

    let automaticReader = ArchiveReader(
        readOptions: .automaticHeaderEncoding(candidates: legacyEncodingCandidates)
    )
    let automaticEntries = try automaticReader.entries(at: archiveURL)
    #expect(automaticEntries.contains { $0.path == entryPath })

    try explicitReader.extract(archiveURL, to: destinationURL)
    #expect(FileManager.default.fileExists(atPath: destinationURL.appendingPathComponent(entryPath).path))
}

@Test
func rejectsParentDirectoryTraversalDuringExtraction() throws {
    let workspace = try makeWorkspace()
    let archiveURL = workspace.appendingPathComponent("unsafe.tar")
    let destinationURL = workspace.appendingPathComponent("output", isDirectory: true)
    let escapedURL = workspace.appendingPathComponent("escape.txt")

    try writeTarArchive(
        entries: [
            .regular(path: "../escape.txt", contents: Data("escape\n".utf8)),
        ],
        to: archiveURL
    )

    var rejected = false

    do {
        try ArchiveReader().extract(archiveURL, to: destinationURL)
    } catch ArchiveError.unsafeEntryPath("../escape.txt") {
        rejected = true
    }

    #expect(rejected)
    #expect(!FileManager.default.fileExists(atPath: escapedURL.path))
}

private func makeWorkspace() throws -> URL {
    let workspace = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    return workspace
}

private func run(
    _ executablePath: String,
    arguments: [String],
    currentDirectory: URL? = nil
) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory
    try process.run()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)
}

private func posixPermissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require(attributes[.posixPermissions] as? Int) & 0o777
}

private func fixtureURL(named name: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
}

private var shiftJISEncoding: String.Encoding {
    .shiftJIS
}

private var gbkEncoding: String.Encoding {
    String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GBK_95.rawValue)
        )
    )
}

private var legacyEncodingCandidates: [String.Encoding] {
    [shiftJISEncoding, gbkEncoding]
}

private func encodedPathBytes(_ path: String, encoding: String.Encoding) throws -> Data {
    try #require(path.data(using: encoding))
}

private struct ZipEntry {
    let pathBytes: Data
    let contents: Data
}

private struct ZipCentralDirectoryEntry {
    let pathBytes: Data
    let contents: Data
    let crc32: UInt32
    let localHeaderOffset: UInt32
}

private func writeStoredZipArchive(
    entries: [ZipEntry],
    to archiveURL: URL
) throws {
    var archive = Data()
    var centralDirectoryEntries: [ZipCentralDirectoryEntry] = []

    for entry in entries {
        let localHeaderOffset = UInt32(archive.count)
        let crc = crc32(entry.contents)

        appendUInt32(0x04034B50, to: &archive)
        appendUInt16(20, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt32(crc, to: &archive)
        appendUInt32(UInt32(entry.contents.count), to: &archive)
        appendUInt32(UInt32(entry.contents.count), to: &archive)
        appendUInt16(UInt16(entry.pathBytes.count), to: &archive)
        appendUInt16(0, to: &archive)
        archive.append(entry.pathBytes)
        archive.append(entry.contents)

        centralDirectoryEntries.append(
            ZipCentralDirectoryEntry(
                pathBytes: entry.pathBytes,
                contents: entry.contents,
                crc32: crc,
                localHeaderOffset: localHeaderOffset
            )
        )
    }

    let centralDirectoryOffset = UInt32(archive.count)

    for entry in centralDirectoryEntries {
        appendUInt32(0x02014B50, to: &archive)
        appendUInt16(20, to: &archive)
        appendUInt16(20, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt32(entry.crc32, to: &archive)
        appendUInt32(UInt32(entry.contents.count), to: &archive)
        appendUInt32(UInt32(entry.contents.count), to: &archive)
        appendUInt16(UInt16(entry.pathBytes.count), to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt32(0, to: &archive)
        appendUInt32(entry.localHeaderOffset, to: &archive)
        archive.append(entry.pathBytes)
    }

    let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset

    appendUInt32(0x06054B50, to: &archive)
    appendUInt16(0, to: &archive)
    appendUInt16(0, to: &archive)
    appendUInt16(UInt16(entries.count), to: &archive)
    appendUInt16(UInt16(entries.count), to: &archive)
    appendUInt32(centralDirectorySize, to: &archive)
    appendUInt32(centralDirectoryOffset, to: &archive)
    appendUInt16(0, to: &archive)

    try archive.write(to: archiveURL)
}

private func appendUInt16(_ value: UInt16, to data: inout Data) {
    var littleEndianValue = value.littleEndian
    withUnsafeBytes(of: &littleEndianValue) { bytes in
        data.append(contentsOf: bytes)
    }
}

private func appendUInt32(_ value: UInt32, to data: inout Data) {
    var littleEndianValue = value.littleEndian
    withUnsafeBytes(of: &littleEndianValue) { bytes in
        data.append(contentsOf: bytes)
    }
}

private func crc32(_ data: Data) -> UInt32 {
    var crc = UInt32.max

    for byte in data {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
            if crc & 1 == 0 {
                crc >>= 1
            } else {
                crc = (crc >> 1) ^ 0xEDB88320
            }
        }
    }

    return crc ^ UInt32.max
}

private func writeTarArchive(
    entries: [TarEntry],
    to archiveURL: URL
) throws {
    var archive = Data()

    for entry in entries {
        archive.append(tarHeader(for: entry))
        archive.append(entry.contents)

        let padding = (512 - (entry.contents.count % 512)) % 512
        archive.append(Data(repeating: 0, count: padding))
    }

    archive.append(Data(repeating: 0, count: 1024))
    try archive.write(to: archiveURL)
}

private enum ArchiveStreamingTestError: Error {
    case expected
}

private struct TarEntry {
    let path: String
    let contents: Data
    let typeFlag: String
    let linkName: String
    let permissions: Int
    let uid: Int
    let gid: Int
    let userName: String
    let groupName: String

    static func regular(
        path: String,
        contents: Data,
        permissions: Int = 0o644,
        uid: Int = 0,
        gid: Int = 0,
        userName: String = "",
        groupName: String = ""
    ) -> Self {
        Self(
            path: path,
            contents: contents,
            typeFlag: "0",
            linkName: "",
            permissions: permissions,
            uid: uid,
            gid: gid,
            userName: userName,
            groupName: groupName
        )
    }

    static func directory(
        path: String,
        permissions: Int = 0o755,
        uid: Int = 0,
        gid: Int = 0,
        userName: String = "",
        groupName: String = ""
    ) -> Self {
        Self(
            path: path,
            contents: Data(),
            typeFlag: "5",
            linkName: "",
            permissions: permissions,
            uid: uid,
            gid: gid,
            userName: userName,
            groupName: groupName
        )
    }

    static func symlink(
        path: String,
        target: String,
        permissions: Int = 0o777,
        uid: Int = 0,
        gid: Int = 0,
        userName: String = "",
        groupName: String = ""
    ) -> Self {
        Self(
            path: path,
            contents: Data(),
            typeFlag: "2",
            linkName: target,
            permissions: permissions,
            uid: uid,
            gid: gid,
            userName: userName,
            groupName: groupName
        )
    }
}

private func tarHeader(for entry: TarEntry) -> Data {
    var header = Data(repeating: 0, count: 512)

    write(entry.path, to: &header, offset: 0, length: 100)
    writeOctal(entry.permissions, to: &header, offset: 100, length: 8)
    writeOctal(entry.uid, to: &header, offset: 108, length: 8)
    writeOctal(entry.gid, to: &header, offset: 116, length: 8)
    writeOctal(entry.contents.count, to: &header, offset: 124, length: 12)
    writeOctal(0, to: &header, offset: 136, length: 12)
    header.replaceSubrange(148..<156, with: Data(repeating: 0x20, count: 8))
    write(entry.typeFlag, to: &header, offset: 156, length: 1)
    write(entry.linkName, to: &header, offset: 157, length: 100)
    write("ustar", to: &header, offset: 257, length: 6)
    write("00", to: &header, offset: 263, length: 2)
    write(entry.userName, to: &header, offset: 265, length: 32)
    write(entry.groupName, to: &header, offset: 297, length: 32)

    let checksum = header.reduce(0) { $0 + Int($1) }
    writeChecksum(checksum, to: &header)

    return header
}

private func write(_ string: String, to data: inout Data, offset: Int, length: Int) {
    let bytes = Array(string.utf8.prefix(length))
    data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
}

private func writeOctal(_ value: Int, to data: inout Data, offset: Int, length: Int) {
    let octal = String(value, radix: 8)
    let padded = String(repeating: "0", count: max(0, length - 1 - octal.count)) + octal
    write(padded, to: &data, offset: offset, length: length - 1)
}

private func writeChecksum(_ value: Int, to data: inout Data) {
    let octal = String(value, radix: 8)
    let padded = String(repeating: "0", count: max(0, 6 - octal.count)) + octal
    write(padded, to: &data, offset: 148, length: 6)
    data[154] = 0
    data[155] = 0x20
}
