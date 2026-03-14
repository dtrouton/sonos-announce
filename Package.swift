// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SonosAnnounce",
    platforms: [.macOS(.v13), .iOS(.v16)],
    targets: [
        .executableTarget(
            name: "SonosAnnounce",
            path: "Sources",
            exclude: ["Info.plist"]
        )
    ]
)
