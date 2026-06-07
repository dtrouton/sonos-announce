// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SonosAnnounce",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "SonosKit", targets: ["SonosKit"]),
    ],
    targets: [
        .target(
            name: "SonosKit",
            path: "Sources/SonosKit"
        ),
        .testTarget(
            name: "SonosKitTests",
            dependencies: ["SonosKit"],
            path: "Tests/SonosKitTests"
        ),
        .executableTarget(
            name: "SonosAnnounce",
            dependencies: ["SonosKit"],
            path: "apps/macOS",
            exclude: ["Info.plist"]
        ),
    ]
)
