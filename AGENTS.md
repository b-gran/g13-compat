# AI Coding Agent Instructions for `g13-compat`

## General guidelines for agents
* Do NOT run git commands in a shell. Do NOT use any available git tools.

## 1. Purpose & High-Level Architecture
Implements Logitech G13 keypad support on macOS in Swift: HID discovery, vendor report parsing fallback, key/macro mapping, joystick-to-key translation, and synthetic keyboard output via two interchangeable backends (CGEvent vs virtual HID). Three deliverables:
- Library target `G13HID` (core logic, fully unit tested).
- `G13HIDApp` (SwiftUI minimal front-end).
- `G13HIDDaemon` (headless executable).

Primary components (all under `Sources/G13HID/`):
- `HIDDevice`: Orchestrates device detection, registers callbacks, feeds raw input to `RawReportParser`, `KeyMapper`, and `JoystickController`. Maintains cached config & performs fallback axis extraction.
- `G13VendorReportParser` (`RawReportParser.swift`): Diffs 7‑byte vendor reports when macOS fails to expose per-button elements; maps (byte,bit) → G key via `G13BitToGKeyMapping`.
- `KeyMapper`: Transforms synthesized `HIDInputData` for button usage page into `KeyboardAction` and dispatches via `KeyboardActionExecutor`.
- `KeyboardActionExecutor`: Uniform execution of actions (tap/down/up/macro) using a `KeyboardOutput` + `MacroEngine`.
- `KeyboardOutput` protocol + implementations: `CGEventKeyboard` (no entitlement, needs Accessibility) and `VirtualKeyboard` (IOHIDUserDevice, requires entitlement; provides 6‑key rollover descriptor). Factory: `KeyboardOutputFactory` with HID→CGEvent fallback.
- `MacroEngine`: Asynchronous macro runner with cancellable delay & per‑character text typing slices; completion callback surfaces success/cancellation.
- `JoystickController`: Converts analog (X,Y) to cardinal/diagonal key holds. Two modes: duty-cycle (secondary key gated by ratio) and hold (segment chaining for continuous rotation). Includes throttling (`maxEventsPerSecond`).
- `Logger`: File + console with level + optional size rotation (single backup) & env configuration.
- `ConfigManager`: Single JSON load (default path `~/.g13-config.json`); exposes `G13Config` holding macros, G key actions, joystick settings, keyboard mode.

## 2. Data & Flow Patterns
1. Raw HID callback → `HIDDevice.handleInput`.
2. If vendor 7‑byte fallback: parser emits `GKeyStateChange` → synthesized `HIDInputData` with usagePage 0x09 routed to `KeyMapper.processInput`.
3. `KeyMapper` guards press/release (tracks `pressedGKeys`) then emits `KeyboardAction` → `KeyboardActionExecutor.perform`.
4. Executor either immediately invokes `KeyboardOutput.*` or dispatches macro to `MacroEngine` (async group for delays/text slices). Tap releases are always asynchronous.
5. Joystick values (standard axes or vendor heuristic bytes[0..1]) feed `JoystickController.updateJoystickRaw` → dynamic key press/release scheduling (timers for duty-cycle). Hold mode re-anchors every 90° span for continuous circular motion.

## 3. Configuration & Environment Conventions
- Config file structure: see `example-config.json` for full schema including nested `joystick.events` object (distinguishes duty-cycle vs hold).
- Env vars (read once at startup):
  - `G13_LOG_LEVEL` (`debug|info|warn|error`).
  - `G13_LOG_APPEND` (true/1 to append vs truncate).
  - `G13_LOG_MAX_BYTES` (>1024 triggers single-file rotation to `.1`).
  - `G13_TAP_DELAY_MS` (5–250 bounds) unified tap delay for both keyboard outputs.
- Keyboard output selection: `keyboardOutputMode` (`cgEvent` default; `hidDevice` attempts entitlement then falls back automatically).

## 4. Testing Patterns
Run: `swift test`. Tests intentionally isolate logic (no entitlement required):
- Parser diffing: `G13VendorReportParserTests` verifies bit → G key mapping & change ordering.
- Action dispatch: `KeyboardActionExecutorTests` uses `MockKeyboardOutput` (see tests directory) to assert tap/down/up/macro semantics & error propagation.
- Joystick algorithms: `JoystickControllerTests` validate deadzone, ratio math, diagonals, duty-cycle behavior.
- Additional macro cancellation, mapping table, and continuous rotation tests exist (see other test files). Entitlement-dependent paths are skipped gracefully.
Conventions: test names use descriptive sentences (`testSingleBitPressAndRelease`). Expectations rely on `XCTestExpectation` for async macro completion.

## 5. Error & Logging Conventions
- Virtual keyboard errors surfaced via `VirtualKeyboard.KeyboardError` (e.g. `.failedToCreateDevice`, `.reportSendFailed(code)`); CGEvent maps failures to `KeyboardError` (accessibility denied, mapping). Executor converts missing macro / invalid key to `KeyboardActionError`.
- Use `logDebug` for high-frequency instrumentation (parser bit diffs, vendor joystick) so production runs can filter with higher `G13_LOG_LEVEL`.
- Fallback decisions (e.g., HID creation failure) always logged with clear human-readable guidance.

## 6. Extension Points & Safe Modification Guidelines
When adding new behavior:
- New macro action: extend `MacroAction` (update `CodingKeys`, encode/decode, and integrate into `executeActionSyncOrSchedule`). Provide a test in `MacroEngineTests` + example JSON.
- New joystick mode: add case to `JoystickConfig.EventsMode` (maintain backward compatibility with existing decode logic) and branch in `JoystickController.configure`.
- New keyboard output backend: conform to `KeyboardOutput` (respect async `tapKey` signature) and expand `KeyboardOutputMode` + factory; add focused tests with a mock device if entitlement not feasible.
- Parser changes: update `BitCoordinateMapping.swift`; ensure `MappingTableTests` still covers all 22 G keys uniquely.

## 7. Style & Coding Patterns
- Enum-based modeling (e.g., `KeyboardAction`, `MacroAction`, `JoystickConfig.EventsMode`) with Codable for config-driven extensibility.
- Single responsibility layering: parsing → mapping → execution; keep new logic within its layer (avoid putting mapping logic inside `HIDDevice`).
- Asynchronous scheduling uses `DispatchQueue.global(qos: .userInitiated).asyncAfter` with small slices (10ms) for responsiveness; mimic this for new delay-like constructs.

## 10. What NOT to Change Without Discussion
- HID report descriptor in `VirtualKeyboard` (must remain valid boot keyboard unless intentionally expanding).
- Mapping table `G13BitToGKeyMapping` unless hardware evidence supports changes (adjust tests accordingly).
- Public Codable config schema fields (additive only to preserve existing user config files).