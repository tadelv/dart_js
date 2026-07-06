// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "flutter_js",
  platforms: [
    .macOS("10.15")
  ],
  products: [
    .library(name: "flutter-js", targets: ["flutter_js"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "flutter_js",
      dependencies: []
    )
  ]
)
