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

## Virtual HID Device Implementation

The VirtualKeyboard now uses **actual IOHIDUserDevice APIs** to create a real virtual keyboard device.

### Key Implementation Details

1. **C Function Declarations**
   - Uses `@_silgen_name` to access `IOHIDUserDeviceCreate` and `IOHIDUserDeviceHandleReport`
   - These functions exist in IOKit but aren't exposed to Swift by default

2. **Device Properties**
   - Uses placeholder VID/PID (0x1234/0x5678) - **change these in production**
   - Includes all required properties: PrimaryUsagePage, PrimaryUsage, MaxReportSizes
   - Boot keyboard descriptor with 6-key rollover

3. **Stable Key Ordering**
   - Pressed keys are sorted before building reports to prevent flickering
   - Avoids nondeterministic behavior from Set ordering

4. **Reliable Timing**
   - Key tap delay increased to 10ms for reliable registration
   - Prevents keys being missed by the OS

### Required: Entitlement

**CRITICAL**: This code requires the `com.apple.developer.hid.virtual.device` entitlement.

Without this entitlement, `IOHIDUserDeviceCreate` will fail at runtime.

#### How to Add the Entitlement

**Option A: Xcode Project**
1. Select your target
2. Go to Signing & Capabilities tab
3. Click "+ Capability"
4. Add "HID Virtual Device" capability

**Option B: Manual Entitlements File**
See [G13HIDApp.entitlements](G13HIDApp.entitlements) for the complete file.

**Option C: Command-line Code Signing**
```bash
# Build first
swift build

# Code sign with entitlements
codesign -s "Developer ID Application: Your Name" \
         -f \
         --entitlements G13HIDApp.entitlements \
         .build/debug/G13HIDApp
```

### Requirements

1. **Apple Developer Program membership** ($99/year)
   - Required to get the entitlement
   - Required for Developer ID certificate

2. **Developer ID Application certificate**
   - Must be installed in your keychain
   - Get from Apple Developer portal

3. **Proper provisioning profile**
   - Must include the HID virtual device entitlement

### Current Implementation Status

✅ **Implemented and working:**
- Real IOHIDUserDevice creation (not a mock)
- Proper HID descriptor (boot keyboard, 6-key rollover)
- Complete device properties with all required keys
- Stable key ordering (sorted array)
- Reliable timing (10ms tap delay)
- Safe report sending with proper memory handling

⚠️ **Requires setup:**
- Entitlement (see above)
- Code signing with Developer ID
- Replace placeholder VID/PID (0x1234/0x5678)

### The Problem Without Entitlement

If you run without the entitlement, you'll see:
```
Error: IOHIDUserDeviceCreate failed
Ensure you have the com.apple.developer.hid.virtual.device entitlement
```

The driver will fall back to **monitor-only mode** where it reads G13 input but cannot send keyboard output.

### Alternatives if Entitlement is Not Available

#### Option A: Use CGEvent API (Simpler Alternative)
Replace VirtualKeyboard with CGEvent-based implementation:
```swift
import CoreGraphics

// Press a key
let keyCode: CGKeyCode = 0x00  // A key
let pressEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
pressEvent?.post(tap: .cghidEventTap)

// Release a key
let releaseEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
releaseEvent?.post(tap: .cghidEventTap)
```

**Pros:**
- No entitlements required
- No code signing needed
- Works immediately
- Simpler API

**Cons:**
- Some games/apps may not accept CGEvent input
- Requires accessibility permissions instead
- Less "authentic" than real HID device
- Uses different key codes (CGKeyCode vs HID usage codes)

#### Option B: Use DriverKit System Extension
More complex but doesn't require this specific entitlement:
- Modern macOS approach (10.15+)
- Uses DriverKit framework
- Different entitlements and deployment model
- Requires installer and user approval
- Out of scope for this basic implementation

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
