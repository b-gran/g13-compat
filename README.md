# G13HID

A Swift package for working with HID (Human Interface Device) devices on macOS.

## Requirements

- macOS 12.0 or later
- Swift 5.5 or later
- Xcode 13.0 or later

## Installation

### Swift Package Manager

Add the following dependency to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "path/to/your/repository", from: "1.0.0")
]
```

## Usage

```swift
import G13HID

let hidDevice = HIDDevice()
// The device will automatically start monitoring for HID devices
// and print information about them when they are connected
```

## Features

- Automatic HID device discovery
- Device connection handling
- Basic device information retrieval (manufacturer, product name, vendor ID, product ID)

## License

This project is available under the MIT license.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. 