// swift-tools-version: 6.0

import PackageDescription

let packageVersion = "0.1.3"
let cArchiveChecksum = "8975d6c92192ee5b1bf1ae2448e88939dfad4bda701539e9b5fc8a9e9f8fdfc9"

let package = Package(
    name: "LibArchiveSwift",
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
