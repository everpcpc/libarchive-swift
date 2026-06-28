// swift-tools-version: 6.0

import PackageDescription

let packageVersion = "0.1.10"
let cArchiveChecksum = "7658e7eab852a881aa7622f61e6bb2bc930daec72f58c8c863a2153cbea69751"

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
