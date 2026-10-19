// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TUUI",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TUUI", targets: ["TUUI"]),
    ],
    dependencies: [
        .package(path: "../TUCore"),
    ],
    targets: [
        .target(name: "TUUI", dependencies: ["TUCore"]),
    ]
)
