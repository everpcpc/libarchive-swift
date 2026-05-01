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
