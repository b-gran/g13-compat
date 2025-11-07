# Keyboard Output Modes

The G13 driver supports two different keyboard output modes that you can switch between via configuration.

## Available Modes

### 1. CGEvent Mode (Default) - `"cgEvent"`

**Pros:**
- ✅ Works immediately, no entitlements needed
- ✅ No code signing required
- ✅ No Apple Developer Program membership needed
- ✅ Perfect for testing and development

**Cons:**
- ⚠️ Requires Accessibility permissions in System Preferences
- ⚠️ Some games/apps may not accept CGEvent input
- ⚠️ Less "authentic" than a real HID device

**When to use:**
- Testing the driver architecture
- Development without Apple Developer Program
- Most desktop applications
- When you don't have the HID entitlement

### 2. HID Device Mode - `"hidDevice"`

**Pros:**
- ✅ Most authentic - acts as a real USB keyboard
- ✅ Accepted by all applications and games
- ✅ No accessibility permissions needed

**Cons:**
- ❌ Requires `com.apple.developer.hid.virtual.device` entitlement
- ❌ Requires Apple Developer Program membership ($99/year)
- ❌ Requires code signing with Developer ID certificate
- ❌ More complex setup

**When to use:**
- Production deployment
- Games that reject CGEvent input
- When you have an Apple Developer Program membership

## How to Switch Modes

### Method 1: Edit Config File (Recommended)

Edit your config file at `~/.g13-config.json`:

```json
{
  "keyboardOutputMode": "cgEvent",  // or "hidDevice"
  "macros": { ... },
  "gKeys": [ ... ],
  "joystick": { ... }
}
```

**Available values:**
- `"cgEvent"` - Use CGEvent API (default, works immediately)
- `"hidDevice"` - Use real HID virtual device (requires entitlement)

### Method 2: Use Example Config

Copy the example config:
```bash
cp example-config.json ~/.g13-config.json
```

Then edit the `keyboardOutputMode` field.

## Testing Each Mode

### Test CGEvent Mode

1. Set config:
   ```json
   "keyboardOutputMode": "cgEvent"
   ```

2. Run the app:
   ```bash
   swift run G13HIDApp
   ```

3. You should see:
   ```
   Keyboard output mode: CGEvent (no entitlement required)
   CGEventKeyboard initialized
   Note: Requires Accessibility permissions...
   ```

4. Grant Accessibility permission:
   - Open System Preferences > Privacy & Security > Accessibility
   - Add and enable your terminal app (Terminal.app or iTerm2, etc.)

5. Test with a G key press - it should output to your active application

### Test HID Device Mode

1. Set config:
   ```json
   "keyboardOutputMode": "hidDevice"
   ```

2. Build and sign:
   ```bash
   swift build
   codesign -s "Developer ID Application: Your Name" \
            --entitlements G13HIDApp.entitlements \
            .build/debug/G13HIDApp
   ```

3. Run:
   ```bash
   .build/debug/G13HIDApp
   ```

4. You should see:
   ```
   Keyboard output mode: HID Device (requires entitlement)
   Virtual keyboard initialized successfully
   ```

5. If you see an error, you're missing the entitlement:
   ```
   Error: IOHIDUserDeviceCreate failed
   Ensure you have the com.apple.developer.hid.virtual.device entitlement
   Failed to create keyboard with mode hidDevice, falling back to CGEvent
   ```

## Automatic Fallback

If HID device creation fails, the driver automatically falls back to CGEvent mode:

```swift
// In your config
"keyboardOutputMode": "hidDevice"

// At runtime (without entitlement)
Keyboard output mode: HID Device (requires entitlement)
Failed to create HID keyboard: failedToCreateDevice
Failed to create keyboard with mode hidDevice, falling back to CGEvent
CGEventKeyboard initialized
```

This ensures the driver always works, even if the preferred mode is unavailable.

## Programmatic Usage

You can also create keyboards directly in code:

```swift
import G13HID

// Create CGEvent keyboard
let cgKeyboard = CGEventKeyboard()
try cgKeyboard.tapKey(.w)

// Create HID keyboard (may fail without entitlement)
if let hidKeyboard = try? VirtualKeyboard() {
    try hidKeyboard.tapKey(.w)
}

// Use factory with automatic fallback
let keyboard = KeyboardOutputFactory.createWithFallback()
try keyboard.tapKey(.w)
```

## Checking Current Mode at Runtime

The driver prints the current mode at startup:

```bash
swift run G13HIDApp 2>&1 | grep "Keyboard output mode"
```

Output:
```
Keyboard output mode: CGEvent (no entitlement required)
```

or

```
Keyboard output mode: HID Device (requires entitlement)
```

## Recommendations

**For Testing/Development:**
Use CGEvent mode (`"cgEvent"`) - it works immediately without any special setup.

**For Production:**
Use HID Device mode (`"hidDevice"`) - get the entitlement and sign your app properly for the most reliable experience.

**Not Sure?**
Start with CGEvent mode. If you encounter games that don't accept the input, then invest in the Apple Developer Program and switch to HID Device mode.

## Troubleshooting

### CGEvent mode not working
- Check Accessibility permissions in System Preferences
- Make sure your terminal app has permission
- Try running with `sudo` (not recommended for production)

### HID Device mode not working
- Verify you have the entitlement in your file
- Check code signing: `codesign -d --entitlements - .build/debug/G13HIDApp`
- Ensure you're using a Developer ID certificate, not a development certificate
- Verify your Apple Developer Program membership is active

### Keys not registering
- Check which mode is active in the startup logs
- Verify your config file has the correct `keyboardOutputMode` value
- Test with a simple application like TextEdit first

## Architecture

Both modes use the same `KeyboardOutput` protocol:

```
KeyboardOutput Protocol
    ├── VirtualKeyboard (HID Device mode)
    └── CGEventKeyboard (CGEvent mode)
```

All other components (MacroEngine, JoystickController, KeyMapper) work with the protocol, so switching modes is transparent to the rest of the system.
