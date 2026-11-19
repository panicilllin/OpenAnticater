// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenAnticater",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "OpenAnticater", targets: ["OpenAnticater"]),
    ],
    targets: [
        // 协议编解码、键码表、设备通信：不依赖界面，可单独测试。
        .target(name: "KnobKit"),
        .executableTarget(
            name: "OpenAnticater",
            dependencies: ["KnobKit"]
        ),
        .executableTarget(
            name: "knobctl",
            dependencies: ["KnobKit"]
        ),
        .testTarget(
            name: "KnobKitTests",
            dependencies: ["KnobKit"]
        ),
    ]
)
