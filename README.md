# LibArchiveSwift

Swift Package wrapper for [libarchive](https://github.com/libarchive/libarchive).

## Installation

Add this package in Xcode:

```text
https://github.com/everpcpc/libarchive-swift
```

Or add it to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/everpcpc/libarchive-swift", from: "0.1.2"),
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

Current Swift API surface:

- `ArchiveReader.entries(at:)`
- `ArchiveEntry.path`
- `ArchiveEntry.size`
- `ArchiveEntry.fileType`
- `ArchiveEntry.permissions`
- `ArchiveEntry.modificationDate`
- `LibArchive.versionString`
- `LibArchive.versionNumber`

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
LIBARCHIVE_VERSION=v3.8.7 scripts/build-libarchive-xcframework.sh
```

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

The checked-in `Artifacts/CArchive.xcframework` currently contains slices for:

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

The checked-in `CArchive.xcframework` is built from upstream libarchive. libarchive is BSD-style licensed, with per-file notices and exceptions in the upstream source tree. This repository includes the upstream notice in `COPYING.libarchive`; keep it with any binary distribution.

The default artifact includes upstream libarchive object code, so downstream redistributors should preserve both files:

- `LICENSE`
- `COPYING.libarchive`

RAR test fixtures under `Tests/LibArchiveTests/Fixtures` are derived from upstream libarchive's test suite and are covered by `COPYING.libarchive`.
