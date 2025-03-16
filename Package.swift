// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "G13HID",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "G13HIDApp",
            targets: ["G13HIDApp"]),
        .library(
            name: "G13HID",
            targets: ["G13HID"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "G13HID",
            dependencies: []),
        .executableTarget(
            name: "G13HIDApp",
            dependencies: ["G13HID"]),
        .testTarget(
            name: "G13HIDTests",
            dependencies: ["G13HID"]),
    ]
) 