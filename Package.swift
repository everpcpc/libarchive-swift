// swift-tools-version: 6.0

import PackageDescription

let packageVersion = "0.1.7"
let cArchiveChecksum = "7863c3c6044d4dc715b4bcf904f40604146df910e85b163980adbb07a38b827e"

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
