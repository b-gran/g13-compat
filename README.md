## G13 Compat (Swift macOS HID & Macro Engine)

An experimental macOS Swift implementation to bring the Logitech G13 keypad back to life: raw HID report parsing, key mapping, joystick handling, macro execution, and synthetic keyboard output via either CGEvent (no entitlement) or a virtual HID keyboard (requires entitlement). All logic is testable with mocks; entitlement-dependent flows are skipped automatically.

---
### Table of Contents
1. Quick Start
2. Architecture Overview
3. Configuration (`example-config.json`)
4. Macro System
5. Keyboard Output Modes
6. Joystick Handling
7. Logging & Environment Variables
8. Testing
9. Limitations / Entitlements
10. Contributing
11. License

---
### 1. Quick Start

```
git clone <repo>
cd g13-compat
swift build
swift run G13HIDApp  # GUI / SwiftUI front-end
```

Or run the daemon (headless):

```
swift run G13HIDDaemon
```

Drop a config at `~/.g13-config.json` (or copy `example-config.json`). Press G keys to see mapped actions executed; check `~/g13-debug.log` for detailed output.

### 2. Architecture Overview

Core modules (under `Sources/G13HID`):
- `HIDDevice`: Detects G13, enumerates elements, parses reports via injected parser.
- `G13VendorReportParser`: Converts raw 7-byte vendor reports into `GKeyStateChange` events (pressed / released).
- `KeyMapper`: Turns G key events into high-level `KeyboardAction` (tap/down/up/macro).
- `KeyboardActionExecutor`: Executes actions using a `KeyboardOutput` + `MacroEngine`.
- `KeyboardOutput` protocol with implementations:
    - `CGEventKeyboard`: Posts CGEvent key presses (needs Accessibility trust).
    - `VirtualKeyboard`: Creates a virtual HID device (needs entitlement) and sends reports.
- `MacroEngine`: Registers & executes macros (sequence of key press/release/tap, delay, text) asynchronously; supports cancellation via `MacroCancellationToken`.
- `JoystickController`: Polls analog values, applies deadzone & duty-cycle gating, emits directional key presses.
- `Logger`: Level-filtered file logger with optional append and size-based rotation.

SwiftUI front-end (`Sources/G13HIDApp`) provides a simple view; `G13HIDDaemon` offers headless execution.

### 3. Configuration (`~/.g13-config.json`)

Key sections:
- `keyboardOutputMode`: `cgEvent` (default) or `hidDevice`.
- `macros`: Named macro definitions (see example). Each action: `{"type": "keyTap"|"keyPress"|"keyRelease"|"delay"|"text", ...}`.
- `gKeys`: Maps G key numbers (1–22) to actions – either direct key tap or macro reference.
- `joystick`: Analog configuration (enabled, deadzone, duty-cycle frequency, optional maxEventsPerSecond throttle, mapping of up/down/left/right). Legacy field `dutyCycleRatio` (from older builds) is ignored if present.

Reload behavior: Config is loaded once at startup and updates via explicit update calls (see `ConfigManager`).

### 4. Macro System
Macro actions (`MacroAction`): `keyPress`, `keyRelease`, `keyTap`, `delay(milliseconds)`, `text`.
- Key taps & delays are scheduled asynchronously (non-blocking).
- Cancellation: Acquire token from `executeMacro(key:token:completion:)`; call `cancel()` to abort remaining scheduled slices/typing.
- Completion callback yields `.success` or `.failure(MacroError)` (including `cancelled` or `invalidKey`).

Example JSON macro:
```json
"sprintJump": {
    "name": "Sprint + Jump",
    "actions": [
        {"type": "keyPress", "key": "w"},
        {"type": "delay", "milliseconds": 50},
        {"type": "keyTap", "key": "space"},
        {"type": "delay", "milliseconds": 200},
        {"type": "keyRelease", "key": "w"}
    ]
}
```

### 5. Keyboard Output Modes

| Mode | Entitlement | Use Case | Notes |
|------|-------------|----------|-------|
| `cgEvent` | None | Fast start, works in many apps | Needs Accessibility permission for synthetic events. Some games may reject events. |
| `hidDevice` | `com.apple.developer.hid.virtual.device` | Higher fidelity device emulation | Requires code signing + entitlement; skipped tests automatically if unavailable. |

Switch via config `keyboardOutputMode`. Fallback logic attempts HID then falls back to CGEvent.

### 6. Joystick Handling
`JoystickController` reads analog axes, applies configurable deadzone (`deadzone`), and emits mapped WASD-style keys. Behavior is selected via a nested `events` object in the joystick config. Disable via `"enabled": false`.

Events modes:
1. Duty-cycle mode (default): Adjacent secondary key is duty-cycled based on angular offset from nearest cardinal.
2. Hold mode: Keys are simply held; a secondary key is added once the angle passes a threshold and eventually replaces the primary near the diagonal.

Fallback axis extraction: On macOS versions where the G13 does not expose separate Generic Desktop X/Y elements, only a 7-byte vendor report (usagePage `0xFF00`) is received. In this case the first two bytes are heuristically treated as X/Y (center ≈ `0x80`) and normalized to the range -1.0..1.0. This enables joystick key emission even without dedicated axis elements. Debug logs prefixed with `VendorJoystick:` show raw and normalized values.

Duty-cycle algorithm (events.dutyCycle* fields):
The joystick now treats the nearest cardinal direction (Right=D, Up=W, Left=A, Down=S) as the primary key which is held continuously while outside the deadzone. A secondary key (adjacent clockwise or counter-clockwise) is duty-cycled based on angular offset from the primary anchor.

Definitions:
- Angle 0° = Right (D), 90° = Up (W), 180° = Left (A), 270° = Down (S).
- The angular difference to the nearest cardinal is clamped to 0–45°. The secondary duty cycle ratio = (absDiff / 45). At 0° no secondary key. At 45° (true diagonal) secondary ratio = 1 (held continuously). At 22.5° ratio ≈ 0.5 (half the time pressed).
- Secondary selection: determined by sign of angular deviation (positive = clockwise from anchor).

Examples:
| Approx Angle | Primary | Secondary | Secondary Ratio | Behavior |
|--------------|---------|-----------|-----------------|----------|
| 90° (Up) | W | — | 0.0 | Hold W only |
| 112.5° (mid between Up and Up-Left) | W | A | 0.5 | Hold W; tap A with 50% duty cycle |
| 135° (Up-Left diagonal) | W | A | 1.0 | Hold W and A continuously |
| 22.5° (mid between Right and Up-Right) | D | W | 0.5 | Hold D; tap W with 50% duty cycle |
| 315° (~Down-Right) | D | S | ratio depends on offset (e.g. 30° => 30/45 ≈ 0.67) | Hold D; S cycles 67% on |

Timing: The secondary ON and OFF phases subdivide the base period (1 / `dutyCycleFrequency`) proportionally to the ratio. Minimum phase length is 5ms to avoid excessively rapid timers.

Event throttling (`maxEventsPerSecond`):
Set an optional cap to reduce total key press/release transitions while preserving the perceived duty-cycle ratio. The controller scales the effective period so that transitions per second do not exceed the cap. Roughly, each full secondary cycle (press+release) counts as 2 events. Example: with `dutyCycleFrequency = 60` and `ratio = 0.5`, naive transitions could be high; if `maxEventsPerSecond = 5`, the period is stretched so cycles per second ≈ `cap / 2` while keeping ON:OFF proportion. Omit or set `null` to disable throttling. Primary key remains continuously held and is not throttled.

Config examples:

Duty-cycle:
```json
"joystick": {
    "enabled": true,
    "deadzone": 0.15,
    "events": {
        "dutyCycleFrequency": 60.0,
        "dutyCycleRatio": 0.5,
        "maxEventsPerSecond": 5
    },
    "upKey": "w",
    "downKey": "s",
    "leftKey": "a",
    "rightKey": "d"
}
```

Hold mode (no duty cycle timers):
```json
"joystick": {
    "enabled": true,
    "deadzone": 0.15,
    "events": {
        "hold": true,
        "diagonalAnglePercent": 0.15
    },
    "upKey": "w",
    "downKey": "s",
    "leftKey": "a",
    "rightKey": "d"
}
```

Hold mode semantics:
- `diagonalAnglePercent` is a fraction (0–1) of the 90° span between cardinals.
- Secondary key engages at `addThreshold = diagonalAnglePercent * 90°` of angular drift from the nearest cardinal.
- Primary key releases at `dropThreshold = (1 - diagonalAnglePercent) * 90°` (secondary then becomes the sole primary).
- At most two keys are ever held simultaneously.

### 7. Logging & Environment Variables
Log file: `~/g13-debug.log`

Environment variables:
- `G13_LOG_LEVEL` = `debug|info|warn|error` (default `info`).
- `G13_LOG_APPEND` = `true|1` to append instead of truncate.
- `G13_LOG_MAX_BYTES` = integer > 1024 for rotation threshold; rotates to `g13-debug.log.1`.
- `G13_TAP_DELAY_MS` = custom tap press→release delay (default 10ms, bounds 5–250).

Sample startup:
```
G13_LOG_LEVEL=debug G13_TAP_DELAY_MS=25 swift run G13HIDDaemon
```

### 8. Testing
Run all tests:
```
swift test
```
Test categories:
- Parsing: Vendor report bit change detection.
- Mapping & Actions: `KeyboardActionExecutorTests`, `KeyMapperTests`.
- Macros: Execution & cancellation (`MacroEngineTests`, `MacroCancellationTests`).
- Virtual keyboard & entitlement-sensitive tests are skipped automatically without entitlement.
- New: Tap completion tests verify callback invocation.

### 9. Limitations / Entitlements
- `hidDevice` mode requires entitlement; without it creation fails and CGEvent fallback is used.
- Some protected or anti-cheat environments may ignore CGEvent-based input.
- Accessibility permission must be granted for CGEvent mode; the logger reports status at initialization.
- Current log rotation keeps only a single backup (`.1`). Multi-generation rotation is a possible enhancement.

### 10. Contributing
Contributions welcome: expand error taxonomy, enhance mapping tables, multi-file log rotation, add Result-based tap completion, CLI tools. Please open issues or PRs. Keep tests green and include coverage for new logic.

### 11. License
MIT (see `LICENSE`).

---
### Minimal Code Example
```swift
import G13HID

let output = KeyboardOutputFactory.createWithFallback()
let macroEngine = MacroEngine(keyboard: output)
macroEngine.registerMacro(key: "hello", macro: .typeText("hello"))
macroEngine.executeMacro(key: "hello") { result in
        print("Macro finished: \(result)")
}
```

### Troubleshooting Quick Reference
| Symptom | Check | Fix |
|---------|-------|-----|
| No key events received | Accessibility log line shows denied? | Grant permission in Settings → Privacy & Security → Accessibility |
| Macro never completes | Cancellation token used? | Ensure not cancelled; inspect log for `cancelled` error |
| High CPU on joystick | Duty-cycle values too high | Adjust `dutyCycleFrequency` or increase deadzone |
| Log grows indefinitely | Rotation disabled | Set `G13_LOG_MAX_BYTES` |

---
For detailed refactor history and remaining tasks see `REFACTOR.md`.