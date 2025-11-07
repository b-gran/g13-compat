# G13 Virtual Keyboard Implementation

This document describes the implementation of the virtual keyboard driver for the Logitech G13.

## Architecture

The driver consists of several key components:

### 1. VirtualKeyboard ([VirtualKeyboard.swift](Sources/G13HID/VirtualKeyboard.swift))
- Creates a virtual HID keyboard device using IOHIDUserDevice
- Implements USB HID keyboard descriptor (6-key rollover)
- Provides methods to press, release, and tap keys
- Supports modifier keys (Ctrl, Shift, Alt, Command)
- Translates string key names to HID usage codes

### 2. JoystickController ([JoystickController.swift](Sources/G13HID/JoystickController.swift))
- Converts joystick position to WASD key presses
- Implements duty cycle output at configurable frequency
- Supports 8 directions (cardinal + diagonals)
- Configurable deadzone
- Normalizes raw joystick values (0-255) to -1.0 to 1.0

### 3. MacroEngine ([MacroEngine.swift](Sources/G13HID/MacroEngine.swift))
- Executes macro sequences on G key presses
- Supports actions: keyPress, keyRelease, keyTap, delay, text
- Runs macros asynchronously on dedicated queue
- JSON serializable macro definitions

### 4. KeyMapper ([KeyMapper.swift](Sources/G13HID/KeyMapper.swift))
- Maps G13 button inputs to keyboard actions
- Tracks pressed G keys
- Routes inputs to macros or simple key taps
- Processes HID input data from G13

### 5. ConfigManager ([ConfigManager.swift](Sources/G13HID/ConfigManager.swift))
- Loads/saves configuration from JSON file
- Default config path: `~/.g13-config.json`
- Manages G key mappings, macros, and joystick settings
- Supports import/export of configurations

## Configuration File Format

```json
{
  "macros": {
    "macro1": {
      "name": "Example Macro",
      "actions": [
        {"type": "keyPress", "key": "w"},
        {"type": "delay", "milliseconds": 100},
        {"type": "keyRelease", "key": "w"},
        {"type": "keyTap", "key": "space"},
        {"type": "text", "text": "hello"}
      ]
    }
  },
  "gKeys": [
    {"keyNumber": 1, "action": {"type": "keyTap", "key": "f1"}},
    {"keyNumber": 2, "action": {"type": "macro", "macroName": "macro1"}},
    {"keyNumber": 3, "action": {"type": "disabled"}}
  ],
  "joystick": {
    "enabled": true,
    "deadzone": 0.15,
    "dutyCycleFrequency": 60.0,
    "dutyCycleRatio": 0.5,
    "upKey": "w",
    "downKey": "s",
    "leftKey": "a",
    "rightKey": "d"
  }
}
```

## Key Features

### Joystick WASD Mapping
The joystick uses a duty cycle approach to simulate key presses:
- Direction calculated from angle (8 directions)
- Keys pressed/released at specified frequency (default 60Hz)
- Configurable duty cycle ratio for press/release timing
- Deadzone prevents drift when joystick is centered

### Macro System
Macros support multiple action types:
- **keyPress**: Hold a key down
- **keyRelease**: Release a held key
- **keyTap**: Quick press and release
- **delay**: Wait for milliseconds
- **text**: Type a string of characters

### G Key Mapping
Each of the 22 G keys can be configured to:
- Tap a specific key
- Execute a macro
- Be disabled

## Important Limitation: IOHIDUserDevice

**CRITICAL**: The `IOHIDUserDeviceCreate` and `IOHIDUserDeviceHandleReport` functions are **not publicly available** in the standard IOKit framework on macOS.

### The Problem
Creating virtual HID devices requires one of the following:

1. **DriverKit System Extension (Recommended for macOS 10.15+)**
   - Modern approach using DriverKit framework
   - Requires signing with special entitlements
   - Must be distributed via developer-signed installer
   - User must approve system extension in Security preferences

2. **Kernel Extension (Deprecated)**
   - Requires special signing certificate from Apple
   - Being phased out by Apple
   - Not recommended for new projects

3. **Private APIs (Not Recommended)**
   - Using undocumented APIs
   - Requires SIP disabled
   - May break in future macOS versions

### Current Implementation
The current code includes a **mock implementation** that will fail at runtime. To make this work, you need to:

#### Option A: Use DriverKit (Recommended)
1. Create a DriverKit extension target in Xcode
2. Implement `IOUserHIDDevice` subclass
3. Get appropriate entitlements from Apple
4. Sign with Developer ID Application certificate
5. Package as system extension installer

#### Option B: Use CGEvent (Simpler Alternative)
Instead of creating a virtual HID device, you could use `CGEvent` to simulate keyboard input:
- Simpler to implement
- No special entitlements required
- Works in the same process
- May be flagged by some applications

Example CGEvent approach:
```swift
let keyCode: CGKeyCode = 0x00  // A key
let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
event?.post(tap: .cghidEventTap)
```

### Next Steps
You need to choose an implementation strategy:

1. **If you want a proper solution**: Implement DriverKit system extension
2. **If you want something quick**: Use CGEvent API instead
3. **For testing**: Current mock allows code to compile and run in monitor mode

## Testing

All components have comprehensive test coverage:
- VirtualKeyboardTests: Key code mapping, press/release operations
- JoystickControllerTests: Direction detection, duty cycle, raw value conversion
- MacroEngineTests: Macro execution, error handling, action types
- KeyMapperTests: G key mapping, button press/release tracking
- ConfigManagerTests: JSON serialization, file I/O, config updates

Run tests with:
```bash
swift test
```

Note: Tests that require actual virtual keyboard creation will be skipped until IOHIDUserDevice is properly implemented.

## Usage Example

```swift
import G13HID

// Initialize device (loads config from ~/.g13-config.json)
let device = try HIDDevice()

// Access components
if let config = device.getConfigManager() {
    // Modify configuration
    var newConfig = config.getConfig()
    newConfig.joystick.deadzone = 0.2
    try config.updateConfig(newConfig)
}

// Manually execute a macro
if let macro = device.getMacroEngine() {
    macro.executeMacro(key: "macro1") { result in
        switch result {
        case .success():
            print("Macro executed")
        case .failure(let error):
            print("Error: \(error)")
        }
    }
}
```

## Building

```bash
# Build
swift build

# Run
.build/debug/G13HIDApp

# Tests
swift test
```

## Files Created

### Core Library (Sources/G13HID/)
- VirtualKeyboard.swift - Virtual HID keyboard device
- JoystickController.swift - Joystick to WASD conversion
- MacroEngine.swift - Macro execution engine
- KeyMapper.swift - G key input mapping
- ConfigManager.swift - Configuration management
- HIDDevice.swift - Main device integration (modified)

### Tests (Tests/G13HIDTests/)
- VirtualKeyboardTests.swift
- JoystickControllerTests.swift
- MacroEngineTests.swift
- KeyMapperTests.swift
- ConfigManagerTests.swift

## Configuration

Default configuration is created at `~/.g13-config.json` on first run with sensible defaults:
- G1-G12 → F1-F12
- G13-G22 → 1-0
- Joystick → WASD with 0.15 deadzone, 60Hz duty cycle
