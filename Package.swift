// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SizeUp2",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "SizeUp2", path: "Sources/SizeUp2")
    ]
)
