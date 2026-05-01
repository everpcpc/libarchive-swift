// swift-tools-version: 6.0

import PackageDescription

let packageVersion = "0.1.5"
let cArchiveChecksum = "664a1ebca15d71e20bfd686000a495ffd92bf2fb9a223fcc4fc69a64f86c0427"

let package = Package(
    name: "LibArchive",
    platforms: [
        .iOS(.v13),
        .macOS(.v11),
        .tvOS(.v13),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "LibArchive",
            targets: ["LibArchive"]
        ),
    ],
    targets: [
        .target(
            name: "LibArchive",
            dependencies: ["CArchive"],
            linkerSettings: [
                .linkedLibrary("z"),
            ]
        ),
        .binaryTarget(
            name: "CArchive",
            url: "https://github.com/everpcpc/libarchive-swift/releases/download/\(packageVersion)/CArchive.xcframework.zip",
            checksum: cArchiveChecksum
        ),
        .testTarget(
            name: "LibArchiveTests",
            dependencies: ["LibArchive"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
