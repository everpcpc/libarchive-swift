// swift-tools-version: 6.0

import PackageDescription

let packageVersion = "0.1.9"
let cArchiveChecksum = "b9e383ddc4f1657a9dcfd26d377900041cf8b9ce8134858d44257d7518682311"

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
