// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Transcriber",
  platforms: [
    .macOS("26.0")  // macOS 26 (Tahoe) - Required for SpeechAnalyzer API
  ],
  products: [
    .executable(
      name: "Transcriber",
      targets: ["Transcriber"]
    )
  ],
  targets: [
    .executableTarget(
      name: "Transcriber",
      dependencies: []
    )
  ]
)
