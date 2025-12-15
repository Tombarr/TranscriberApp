// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "TranscriberCLI",
  platforms: [
    .macOS("26.0")  // macOS 26 (Tahoe) - Required for SpeechAnalyzer API
  ],
  products: [
    .executable(
      name: "TranscriberCLI",
      targets: ["TranscriberCLI"]
    )
  ],
  targets: [
    .executableTarget(
      name: "TranscriberCLI",
      dependencies: []
    )
  ]
)
