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
        // NOTE: The macOS app (apps/macOS) is temporarily NOT a build target during
        // the SonosKit extraction (Tasks 2-12) so `swift test` stays green while the
        // app references not-yet-public types. Task 13 restores this executable target
        // and refactors the app onto SonosKit.
        // .executableTarget(
        //     name: "SonosAnnounce",
        //     dependencies: ["SonosKit"],
        //     path: "apps/macOS",
        //     exclude: ["Info.plist"]
        // ),
    ]
)
