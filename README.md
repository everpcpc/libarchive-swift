# LibArchive

Swift Package wrapper for [libarchive](https://github.com/libarchive/libarchive).

## Installation

Add this package in Xcode:

```text
https://github.com/everpcpc/libarchive-swift
```

Or add it to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/everpcpc/libarchive-swift", from: "0.1.5"),
]
```

Then depend on the `LibArchive` product:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "LibArchive", package: "libarchive-swift"),
    ]
)
```

## What is included

This package is structured for Apple platform distribution:

- `CArchive` is a generated static XCFramework built from upstream libarchive.
- `LibArchive` is a Swift 6 source wrapper over the C API.
- The default build enables zlib and disables optional external libraries such as OpenSSL, liblzma, zstd, lz4, libxml2, and expat.

The first supported surface is archive metadata listing for all read formats compiled into the bundled libarchive artifact, with the filters that are available without external helper programs.

## Usage

List entries:

```swift
import Foundation
import LibArchive

let archiveURL = URL(fileURLWithPath: "/path/to/archive.tar.gz")
let entries = try ArchiveReader().entries(at: archiveURL)

for entry in entries {
    print("\(entry.path) \(entry.size) \(entry.fileType)")
}
```

Read libarchive version information:

```swift
import LibArchive

print(LibArchive.versionString)
print(LibArchive.versionNumber)
```

Handle errors:

```swift
do {
    let entries = try ArchiveReader().entries(at: archiveURL)
    print(entries)
} catch let error as ArchiveError {
    print("Archive error: \(error)")
} catch {
    print("Unexpected error: \(error)")
}
```

Extract an archive:

```swift
import Foundation
import LibArchive

let archiveURL = URL(fileURLWithPath: "/path/to/archive.zip")
let destinationURL = URL(fileURLWithPath: "/path/to/output", isDirectory: true)

try ArchiveReader().extract(archiveURL, to: destinationURL)
```

Customize extraction behavior:

```swift
try ArchiveReader().extract(
    archiveURL,
    to: destinationURL,
    options: [
        .preserveModificationTime,
        .preservePermissions,
        .safeWrites,
    ]
)
```

## Swift API coverage

This package deliberately exposes a small Swift-friendly API on top of libarchive. It does not try to mirror every C function one by one.

Supported Swift APIs:

- `ArchiveReader.entries(at:)`
  - Opens an archive from a file URL.
  - Returns metadata for each entry.
  - Skips entry payloads.
- `ArchiveReader.extract(_:to:options:)`
  - Extracts an archive to a destination directory.
  - Uses libarchive's disk writer.
  - Rejects absolute paths and parent-directory traversal before writing.
  - Checks symlink and hardlink targets before writing.
- `ArchiveEntry.path`
- `ArchiveEntry.size`
- `ArchiveEntry.fileType`
- `ArchiveEntry.permissions`
- `ArchiveEntry.modificationDate`
- `ArchiveExtractionOptions`
  - `preserveOwner`
  - `preservePermissions`
  - `preserveModificationTime`
  - `noOverwrite`
  - `noOverwriteNewer`
  - `unlinkExisting`
  - `preserveACL`
  - `preserveFileFlags`
  - `preserveExtendedAttributes`
  - `sparse`
  - `safeWrites`
- `LibArchive.versionString`
- `LibArchive.versionNumber`

Extraction rejects unsafe entry paths by default, including absolute paths and parent-directory traversal. Symlink and hardlink targets are also checked before writing.

Not yet wrapped as Swift APIs:

- Streaming entry data to memory or a caller-provided sink.
- Creating archives.
- Appending files to archives.
- Writing archive entries.
- Selecting a specific read format or filter per operation.
- Password/passphrase APIs for encrypted archives.
- Progress callbacks and cancellation.
- Custom libarchive callbacks for open/read/seek/close.
- In-memory archive input.
- Extended metadata wrappers for ACLs, xattrs, file flags, sparse maps, digests, uid/gid/uname/gname, hardlinks, symlink metadata, birth/ctime/atime, and macOS metadata.
- Low-level access to `struct archive` or `struct archive_entry` handles.

The underlying `CArchive` target contains the upstream C headers, but it is an implementation dependency of the Swift wrapper target. Public package consumers should treat `LibArchive` as the supported API surface.

## Supported formats

Enabled archive formats:

- 7zip
- ar
- cab
- cpio
- empty
- iso9660
- lha
- mtree
- rar
- rar5
- tar, including ustar, pax, and gnutar variants
- warc
- zip

Enabled filters:

- none
- gzip
- compress
- uu
- rpm

The XCFramework is built with zlib enabled and most optional external dependencies disabled. This keeps iOS, tvOS, and visionOS integration predictable for the first release.

RAR support is read-only, matching libarchive's upstream capability.

Filters that require disabled optional libraries or external helper programs are not enabled by the Swift wrapper in the default artifact. That means bzip2, xz/lzma, zstd, lz4, lzip, lzop, lrzip, and grzip are intentionally not advertised as supported by this package yet.

The low-level libarchive raw reader is not enabled by default because upstream `archive_read_support_format_all` also omits it; registering raw would make arbitrary non-archive files appear readable as single-entry streams. Xar is also not enabled in the default artifact because it requires XML parser support, which is intentionally disabled for this dependency-light build.

## Rebuild the binary target

Run:

```sh
scripts/build-libarchive-xcframework.sh
```

The script fetches libarchive `v3.8.7` by default and writes:

```text
Artifacts/CArchive.xcframework
```

You can override the upstream version:

```sh
LIBARCHIVE_VERSION=v3.8.7 \
LIBARCHIVE_SHA256=d3a8ba457ae25c27c84fd2830a2efdcc5b1d40bf585d4eb0d35f47e99e5d4774 \
scripts/build-libarchive-xcframework.sh
```

The script downloads the official upstream release tarball and verifies SHA256 before building. It does not use a git checkout.

## Use from Swift

```swift
import LibArchive

let entries = try ArchiveReader().entries(at: archiveURL)
for entry in entries {
    print(entry.path, entry.size, entry.fileType)
}
```

## Platform policy

The package declares:

- iOS 13+
- macOS 11+
- tvOS 13+
- visionOS 1+

The binary compatibility boundary is the generated XCFramework. If you need lower deployment targets or a different slice set, rebuild the artifact with the corresponding environment variables:

```sh
IPHONEOS_DEPLOYMENT_TARGET=12.0 \
TVOS_DEPLOYMENT_TARGET=12.0 \
MACOSX_DEPLOYMENT_TARGET=10.15 \
scripts/build-libarchive-xcframework.sh
```

The release asset `CArchive.xcframework.zip` currently contains slices for:

- iOS device and simulator
- macOS universal
- tvOS device and simulator
- visionOS device and simulator

## Dependency policy

The default artifact links zlib and disables most optional dependencies. This keeps iOS/tvOS integration predictable and avoids shipping additional compression libraries in the first version.

Enable more filters only when there is a concrete product requirement and matching test archives:

- xz/lzma: enable `ENABLE_LZMA`
- zstd: enable `ENABLE_ZSTD`
- bzip2: enable `ENABLE_BZip2`
- lz4: enable `ENABLE_LZ4`

## License

This wrapper package is distributed under the BSD 2-Clause License. See `LICENSE`.

The release asset `CArchive.xcframework.zip` is built from upstream libarchive. libarchive is BSD-style licensed, with per-file notices and exceptions in the upstream source tree. This repository includes the upstream notice in `COPYING.libarchive`; keep it with any binary distribution.

The default artifact includes upstream libarchive object code, so downstream redistributors should preserve both files:

- `LICENSE`
- `COPYING.libarchive`

RAR test fixtures under `Tests/LibArchiveTests/Fixtures` are derived from upstream libarchive's test suite and are covered by `COPYING.libarchive`.
