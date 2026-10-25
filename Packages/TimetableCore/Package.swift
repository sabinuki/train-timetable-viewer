// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TimetableCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TimetableCore", targets: ["TimetableCore"]),
    ],
    targets: [
        // 時刻表モデル、運行日判定、次発の算出（UI 非依存）
        .target(name: "TimetableCore"),
        .testTarget(name: "TimetableCoreTests", dependencies: ["TimetableCore"]),
    ]
)
