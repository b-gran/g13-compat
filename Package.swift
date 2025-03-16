// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "G13HID",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "G13HID",
            targets: ["G13HID"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "G13HID",
            dependencies: []),
        .testTarget(
            name: "G13HIDTests",
            dependencies: ["G13HID"]),
    ]
) 