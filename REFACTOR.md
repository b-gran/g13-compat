# Refactoring Plan (Immediate Execution)

This document captures identified code smells and concrete refactor actions to be applied rapidly.

## Core Issues

### Overloaded Responsibilities
`HIDDevice` handles device discovery, element enumeration, raw report parsing, configuration wiring, joystick state, macro/key mapping, and logging. This increases complexity and hinders testability.

### Configuration Fragmentation
Joystick calibration (`JoystickCalibration` / `JoystickSettings`) overlaps with `G13Config.joystick`. Bit mapping for G keys is hard-coded and not externally configurable.

### Error Handling Inconsistency
Mixed silent failures (`try?`) and logging fallbacks. Generic errors like `deviceNotActive` hide root cause.

### Logging Noise
Single file log with verbose emoji-rich messages; no log levels; potential performance impact at high input rates.

### Testability Gaps
Direct IOHID usage inside `HIDDevice` obstructs unit testing. Raw report parsing is private and intertwined with side effects.

### Hard-Coded Mappings
CG key code mapping via large switch; HID→CG mapping not validated automatically; vendor report bit mapping encoded with packed integers.

### Timing & Blocking
Use of `usleep` during tap operations blocks the calling thread. Macro execution lacks cancellation support.

### Resource & State Management
Logger truncates file each run without rotation or append option. Accessibility trust checked per key event instead of cached.

## Prioritized Refactor Targets
1. Extract raw report parsing into its own component with clear interface.
2. Introduce a keyboard action abstraction separating mapping from injection.
3. Implement structured logging with levels to reduce noise.
4. Unify joystick configuration sources and clarify precedence.
5. Replace magic integer bit encoding with descriptive struct.
6. Improve error specificity (creation vs send vs permission).
7. Remove blocking `usleep` calls from main execution path.
8. Add unit tests for parsing, action execution, and configuration.

## Concrete Refactor Actions
1. Create `RawReportParser` protocol and `G13VendorReportParser` implementation returning a list of `GKeyStateChange { gKey: Int, down: Bool }`.
2. Replace inline parsing in `HIDDevice` with injected parser instance.
3. Add `KeyboardAction` enum (keyDown, keyUp, tap, macro(String)).
4. Implement `KeyboardActionExecutor` that uses `KeyboardOutput` + `MacroEngine`.
5. Wrap IOHID interaction behind `HIDSession` protocol; provide real and mock implementations.
6. Introduce `LogLevel` (debug, info, warn, error) and environment variable `G13_LOG_LEVEL` to filter output.
7. Convert packed `(byte<<8)|bit` indices to `struct BitCoordinate { let byte: Int; let bit: Int }` with dictionary mapping.
8. Centralize config reads: fetch once during `HIDDevice` init and pass copies into collaborators.
9. Expand `VirtualKeyboard.KeyboardError` (creationFailed, reportSendFailed(code), notEntitled).
10. Replace `usleep` in tap with scheduling (DispatchQueue.asyncAfter) to avoid blocking.
11. Add cancellation token to `MacroEngine` (store UUID, allow cancel mid-run).
12. Add tests: `G13VendorReportParserTests`, `KeyboardActionExecutorTests`, config migration test, macro cancellation test.
13. Cache Accessibility trust result in `CGEventKeyboard` with timed refresh (e.g. every 2s) rather than per key.
14. Provide optional append mode or size rotation for logger.
15. Reduce duplicate mapping logic: generate CG key code table from a static array and create reverse lookup tests.

## Quick Wins (Immediate Changes)
- Add `LogLevel` and filter debug logs without changing external behavior.
- Extract parsing logic into separate file for clearer boundaries.
- Replace repetitive `config.getConfig()` calls with local variable.
- Improve error messages for virtual keyboard creation.
- Wrap joystick key press/release logging with state change conditional to reduce spam.

## Deferred / Optional Enhancements
- Persist bit mapping table to a JSON file if dynamic learning returns.
- Provide CLI tool `g13ctl` for inspecting state.
- JSON schema validation for config with versioning.

## Testing Strategy
- Unit test parser: feed synthetic 7-byte sequences, assert emitted G key changes.
- Unit test executor: verify proper invocation of `KeyboardOutput.press/release/tap` and macro dispatch.
- Integration test: simulate sequence (G1 down/up, G2 down/up) through HIDDevice with mock session.
- Macro cancellation test: ensure long macro can be aborted cleanly.

## Expected Outcomes
- Reduced `HIDDevice` size and complexity.
- Clear separation of concerns (input parsing vs action execution).
- Faster iteration and safer future changes (mapping table, joystick enhancements).
- Stable test suite without entitlement dependence.

## Risks & Mitigations
- Refactor complexity: mitigate by incremental commits and preserving public API.
- Timing differences from replacing `usleep`: mitigate by maintaining minimum 10ms between tap press/release via async scheduling.
- Log level filtering might hide needed debug info: allow override with `G13_LOG_LEVEL=debug`.

## Summary
By extracting parsing and action execution, introducing structured logging, and clarifying configuration and error handling, the codebase becomes more maintainable and testable while preserving current functionality.
