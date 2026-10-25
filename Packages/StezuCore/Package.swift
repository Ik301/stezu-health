// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "StezuCore",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "StezuCore", targets: ["StezuCore"])
  ],
  targets: [
    .target(name: "StezuCore"),
    .testTarget(name: "StezuCoreTests", dependencies: ["StezuCore"]),
  ]
)
