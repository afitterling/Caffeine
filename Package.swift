// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BreakTimer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BreakTimer",
            path: "Sources/BreakTimer"
        )
    ]
)
