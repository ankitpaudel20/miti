// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MitiBar",
    platforms: [.macOS(.v13)], // MenuBarExtra needs macOS 13
    targets: [.executableTarget(name: "MitiBar", path: "Sources")]
)
