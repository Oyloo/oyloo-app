// swift-tools-version: 6.0
// Describes only the pure core so its tests run on a Mac with `swift test`.
// The app itself is built from project.yml; it compiles Sources/Core
// directly, so there is no package dependency to resolve in Xcode.
import PackageDescription

let package = Package(
    name: "OylooCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "OylooCore", targets: ["OylooCore"])],
    targets: [
        .target(name: "OylooCore", path: "Sources/Core"),
        .testTarget(name: "CoreTests", dependencies: ["OylooCore"], path: "Tests/CoreTests")
    ]
)
