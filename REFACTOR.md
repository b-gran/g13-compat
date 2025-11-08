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

## Scope & Non-Scope
In Scope:
- Internal restructuring (`HIDDevice`, parsing, logging, configuration flow)
- New small types (`RawReportParser`, `KeyboardAction`, `LogLevel`, `BitCoordinate`)
- Test additions (unit + light integration with mocks)
- Non-breaking public API changes (internal-only package consumers)

Out of Scope (defer):
- Changing external configuration file schema (except additive fields)
- Joystick algorithm revamp beyond consolidation
- Macro language new actions
- CLI tooling and JSON schema versioning

## Phased Roadmap
Phase 0: Baseline
- Run current tests, capture coverage %, record build time.

Phase 1: Extraction & Logging (Low Risk)
- Introduce `LogLevel` filtering.
- Isolate raw report parsing into `G13VendorReportParser` used by `HIDDevice`.
- Add parser tests.

Phase 2: Action Layer & Error Clarification
- Add `KeyboardAction` enum + executor.
- Refactor `KeyMapper` to emit `KeyboardAction` instead of directly calling output.
- Expand error cases in `VirtualKeyboard` & `CGEventKeyboard`.
- Add executor tests.

Phase 3: Config & Mapping Cleanup
- Centralize config load (single read) and inject into collaborators.
- Replace packed bit mapping with `BitCoordinate` dictionary.
- Add mapping verification tests.

Phase 4: Macro Cancellation & Non-Blocking Taps
- Add cancellation token to `MacroEngine`.
- Replace `usleep` with async scheduling (maintain minimum 10ms press).
- Add macro cancellation tests.

Phase 5: Polish & Logging Rotation
- Add optional log rotation or append mode.
- Cache Accessibility trust result with TTL.
- Document changes in README & IMPLEMENTATION.

Phase 6: Deferred Enhancements (Optional / separate branch)
- JSON mapping externalization, CLI tooling.

## Interfaces (Draft Contracts)
`protocol RawReportParser { func parse(bytes: [UInt8]) -> [GKeyStateChange] }`
`struct GKeyStateChange { let gKey: Int; let down: Bool }`

`enum KeyboardAction { case keyDown(KeyCode); case keyUp(KeyCode); case tap(KeyCode); case macro(String) }`
`protocol KeyboardActionExecutor { func perform(_ action: KeyboardAction) }`

`enum LogLevel: Int { case debug=0, info, warn, error }`
Environment: `G13_LOG_LEVEL` or default `.info`.

`struct BitCoordinate { let byte: Int; let bit: Int }`
Mapping: `[BitCoordinate: Int /* gKey */]` plus reverse lookup validation.

## Acceptance Criteria (Per Phase)
Phase 1:
- All tests pass; new parser tests cover: single key down, multiple changes, no change -> empty array.
- `HIDDevice` no longer contains raw bit iteration logic.

Phase 2:
- `KeyMapper` emits actions; executor invokes underlying output.
- Errors distinguish creation vs send vs entitlement.
- Tests assert action translation for macro and tap.

Phase 3:
- Single config read verified (search for multiple `readConfig` calls removed).
- Mapping struct present; tests enumerate mapping completeness (22 G keys mapped).

Phase 4:
- Macro cancellation stops execution mid-delay/text.
- Tap operation uses async scheduling; no direct `usleep` in production code path.

Phase 5:
- Log rotation/appending controllable via env var `G13_LOG_APPEND=true`.
- Accessibility trust cached with TTL reducing repeated system calls (>50%).

## Metrics & Observability
- Test count increase: +4 new test files.
- Lines reduced in `HIDDevice.swift` by >=20%.
- Parser cyclomatic complexity < 5.
- Log file size decrease in 60s stress test: debug filtered vs baseline (target >30% reduction).
- Macro cancellation latency < 50ms from request.

## Rollback Strategy
- Each phase committed separately; revert by git revert of phase commits.
- Feature flags: if instability occurs set env `G13_DISABLE_NEW_EXECUTOR=1` to bypass new executor (temporary guard inserted during Phase 2).
- Keep legacy parsing function until Phase 3 complete; remove after stable tests.

## Risk Tracking
- Parser mis-mapping: mitigate with exhaustive test table & reverse lookup.
- Timing regression: measure key tap success rate before/after (manual QA).
- Log rotation file permission issues: default to previous truncate behavior if append fails.

## Task Checklist (Detailed)
- [ ] Phase 0 baseline metrics script (optional)
- [ ] Add `LogLevel` enum and filtering logic in `Logger.swift`
- [ ] Inject log level from env
- [ ] Introduce `RawReportParser.swift`
- [ ] Move parsing code from `HIDDevice` to parser
- [ ] Add `G13VendorReportParserTests.swift`
- [ ] Add `KeyboardAction` enum file
- [ ] Implement `ActionExecutor.swift`
- [ ] Refactor `KeyMapper` to emit actions
- [ ] Add executor tests
- [ ] Expand error enums in keyboard outputs
- [ ] Config centralization (single load, pass references)
- [ ] Replace packed bit mapping with struct dictionary
- [ ] Mapping tests (complete coverage, reverse validation)
- [ ] Add cancellation token to `MacroEngine`
- [ ] Async tap scheduling
- [ ] Macro cancellation tests
- [ ] Logger append/rotation option
- [ ] Accessibility trust caching
- [ ] Documentation updates (README, IMPLEMENTATION, KEYBOARD-OUTPUT-MODES)
- [ ] Remove deprecated legacy parsing code & feature flags

## Testing Additions Summary
- `G13VendorReportParserTests.swift`
- `KeyboardActionExecutorTests.swift`
- `MappingTableTests.swift`
- `MacroCancellationTests.swift`

## Open Questions
- Should macro cancellation abort currently pressed keys or leave them for caller cleanup?
- Do we need configurable tap delay beyond static 10ms? (Could make it part of config.)
- Is log rotation size threshold environment configurable (e.g. `G13_LOG_MAX_BYTES`)?

## Next Step (Upon Merging Plan)
Begin Phase 1 implementation; ensure green tests then proceed sequentially.
