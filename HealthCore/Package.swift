// swift-tools-version: 6.0
import PackageDescription

// Pure analytics core. Foundation only: never import SwiftUI, HealthKit or SwiftData here.
let package = Package(
    name: "HealthCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "HealthCore", targets: ["HealthCore"])
    ],
    targets: [
        .target(name: "HealthCore"),
        .testTarget(name: "HealthCoreTests", dependencies: ["HealthCore"])
    ]
)
