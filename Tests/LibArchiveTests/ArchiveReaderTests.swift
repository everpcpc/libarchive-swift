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

private func fixtureURL(named name: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
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
