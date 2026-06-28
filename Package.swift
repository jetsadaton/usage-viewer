// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UsageViewer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "UsageViewer",
            path: "Sources/UsageViewer"
        )
    ]
)
