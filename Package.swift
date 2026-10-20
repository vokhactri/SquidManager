// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "SquidManager",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/airbnb/swift", from: "1.2.0")
  ],
  targets: [
    .target(name: "SquidCore"),
    .executableTarget(
      name: "SquidManager",
      dependencies: ["SquidCore"],
      resources: [.copy("Resources/squid.svg")]
    ),
    .testTarget(name: "SquidCoreTests", dependencies: ["SquidCore"]),
  ]
)
