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
        .target(
            name: "TimetableCore",
            // 内閣府「国民の祝日」CSV（https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv、Shift_JIS）
            resources: [.copy("Resources/syukujitsu.csv")]
        ),
        .testTarget(name: "TimetableCoreTests", dependencies: ["TimetableCore"]),
    ]
)
