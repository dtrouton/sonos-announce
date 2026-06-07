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
        // Named distinctly from the iOS Xcode app target/scheme ("SonosAnnounce")
        // so Xcode's implicit-dependency resolution never tries to build this
        // macOS (AppKit) executable for the iOS destination.
        .executableTarget(
            name: "SonosAnnounceMac",
            dependencies: ["SonosKit"],
            path: "apps/macOS",
            exclude: ["Info.plist"]
        ),
    ]
)
