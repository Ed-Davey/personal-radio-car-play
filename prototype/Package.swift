// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PersonalRadioCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "PersonalRadioCore",
            path: "Sources",
            exclude: ["PersonalRadioApp.swift", "PrototypeView.swift"]
        ),
        .testTarget(name: "PersonalRadioCoreTests", dependencies: ["PersonalRadioCore"])
    ]
)
