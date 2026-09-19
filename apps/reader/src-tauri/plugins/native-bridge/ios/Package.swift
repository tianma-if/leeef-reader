// swift-tools-version:5.3
import PackageDescription

let package = Package(
  name: "tauri-plugin-native-bridge",
  platforms: [
    .macOS(.v10_13),
    .iOS("15.0"),
  ],
  products: [
    .library(
      name: "tauri-plugin-native-bridge",
      type: .static,
      targets: ["tauri-plugin-native-bridge"])
  ],
  dependencies: [
    .package(name: "Tauri", path: "../.tauri/tauri-api")
  ],
  targets: [
    .target(
      name: "tauri-plugin-native-bridge",
      dependencies: [
        .byName(name: "Tauri")
      ],
      path: "Sources")
  ]
)
