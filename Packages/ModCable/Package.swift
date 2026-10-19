// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ModCable",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ModCable", targets: ["ModCable"]),
    ],
    dependencies: [
        .package(path: "../TUCore"),
        .package(path: "../TUUI"),
        // Vendored unmodified via git subtree (Vendor/WhatCable); only Core + DarwinBackend are used.
        .package(path: "../../Vendor/WhatCable"),
    ],
    targets: [
        .target(
            name: "ModCable",
            dependencies: [
                "TUCore",
                "TUUI",
                .product(name: "WhatCableCore", package: "WhatCable"),
                .product(name: "WhatCableDarwinBackend", package: "WhatCable"),
            ]
        ),
        .testTarget(name: "ModCableTests", dependencies: ["ModCable"]),
    ]
)
