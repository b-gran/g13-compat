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

## Running

1. Build the project: `swift build`
2. Run the app: `.build/debug/G13HIDApp`
3. Mash G keys and joystick to see input logged in UI and in `~/g13-debug.log`

### Accessibility Permission (CGEvent Mode)

If you use `keyboardOutputMode` = `cgEvent` (default), macOS must trust the process for Accessibility:

Steps:
1. Open System Settings → Privacy & Security → Accessibility.
2. If running from Xcode, add Xcode and the built helper app. If running the binary directly, add `.build/debug/G13HIDApp` (or the release build path).
3. Toggle them ON. You may need to quit/relaunch after changing.
4. Confirm the log prints: `✅ Accessibility permission: GRANTED`.

If you still see `AXIsProcessTrusted == false`, remove and re-add the entry, or run once via Finder (Gatekeeper sometimes defers trust until launched via GUI).

### Diagnosing Missing Key Events

Check `~/g13-debug.log` for lines:
* `🔵 CGEventKeyboard.pressKey` / `🔵 CGEventKeyboard.releaseKey` – our internal calls.
* `✅ Posted key down event` – Event actually posted. If these exist but target apps ignore them (especially games), they may reject CGEvent synthesized input.
* `🚫 Cannot post keyDown (AXIsProcessTrusted == false)` – Accessibility permission not granted.

### Virtual HID Device Mode

Switch `keyboardOutputMode` to `hidDevice` in the config to attempt real virtual HID creation. This requires the `com.apple.developer.hid.virtual.device` entitlement and proper code signing. Without it you'll see a warning and an automatic fallback.

### Raw Report Heuristic Parser

Some macOS versions expose only aggregate 7‑byte reports instead of per-button elements for the G13. We added a heuristic parser that logs bit transitions:

```
🧩 Heuristic bit change: byte=0 bit=2 -> G? (provisional #3) DOWN ...
```

Press each G key individually and record which provisional number changes. Once the full map is known we can codify it in `parseRawG13Report` → real G key numbers, then invoke `KeyMapper` directly. Feel free to contribute the finalized mapping.

To disable the extra logging, comment out the `parseRawG13Report` call in `HIDDevice.handleInput`.

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