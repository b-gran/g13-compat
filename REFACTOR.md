#aa Refactoring Plan (Immediate Execution)

This document captures identified code smells and concrete refactor actions to be applied rapidly.

## Progress Snapshot (Nov 7, 2025) (Updated After Macro Cancellation Token)

Completed:
- Phase 1: Structured logging (`LogLevel`, env `G13_LOG_LEVEL`, append mode `G13_LOG_APPEND`) & raw report parsing extraction (`RawReportParser` / `G13VendorReportParser`).
- Parser tests added (`G13VendorReportParserTests`).
- Executor abstraction introduced (`KeyboardActionExecutor` + `KeyboardAction` enum) and integrated into `KeyMapper` (Phase 2 partial).
- Action-layer tests added (`KeyboardActionExecutorTests`).
- Config centralization (single load) implemented.
- Bit mapping struct (`BitCoordinate`) & external dictionary (`G13BitToGKeyMapping`) added.
- Mapping validation tests added (`MappingTableTests`).
- Macro cancellation token implemented with responsive sliced delays.
- Macro cancellation tests added (`MacroCancellationTests`).
- Test suite: 73 tests (6 skipped entitlement-dependent), all passing.

In Progress / Upcoming:
- Remaining Phase 2: Expand error cases in `VirtualKeyboard` & `CGEventKeyboard`.
- Phase 4: Non-blocking taps (replace sliced `usleep` with async scheduling dispatch) still pending.
- Phase 5: Accessibility trust caching & log rotation.

Adjustments:
- Feature flag `G13_DISABLE_NEW_EXECUTOR` not yet implemented (remove from immediate checklist until needed).
- Logger rotation still pending; append mode implemented.
- Legacy inline parsing removed from `HIDDevice` (rollback now relies on git history rather than runtime flag).

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

## Concrete Refactor Actions (Updated)
1. Create `RawReportParser` protocol and `G13VendorReportParser` implementation returning a list of `GKeyStateChange { gKey: Int, down: Bool }`.
2. Replace inline parsing in `HIDDevice` with injected parser instance.
3. Add `KeyboardAction` enum (keyDown, keyUp, tap, macro(String)).
4. Implement `KeyboardActionExecutor` that uses `KeyboardOutput` + `MacroEngine`.
5. (Deferred) Wrap IOHID interaction behind `HIDSession` protocol; provide real and mock implementations. Not started; deprioritized after successful parser extraction.
6. Introduce `LogLevel` (debug, info, warn, error) and environment variable `G13_LOG_LEVEL` to filter output.
7. Convert packed `(byte<<8)|bit` indices to `struct BitCoordinate { let byte: Int; let bit: Int }` with dictionary mapping.
8. Centralize config reads: fetch once during `HIDDevice` init and pass copies into collaborators.
9. Expand `VirtualKeyboard.KeyboardError` (creationFailed, reportSendFailed(code), notEntitled).
10. Replace `usleep` in tap with scheduling (DispatchQueue.asyncAfter) to avoid blocking.
11. Add cancellation token to `MacroEngine` (store UUID, allow cancel mid-run).
12. Add tests: `G13VendorReportParserTests`, `KeyboardActionExecutorTests`, config migration test, macro cancellation test.
13. Cache Accessibility trust result in `CGEventKeyboard` with timed refresh (e.g. every 2s) rather than per key.
14. Provide size rotation for logger (append mode done).
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

## Phased Roadmap (Status Annotated)
Phase 0: Baseline
- Run current tests, capture coverage %, record build time.

Phase 1: Extraction & Logging (Completed)
- Introduced `LogLevel` filtering & append mode.
- Isolated raw report parsing into `G13VendorReportParser` used by `HIDDevice`.
- Added parser tests.

Phase 2: Action Layer & Error Clarification (In Progress)
- Added `KeyboardAction` enum + executor.
- Refactored `KeyMapper` to emit `KeyboardAction` instead of direct output calls.
- Pending: expand error cases in `VirtualKeyboard` & `CGEventKeyboard`.
- Added executor tests.

Phase 3: Config & Mapping Cleanup (Completed Core Items)
- Centralized config load (single read) and injected into collaborators.
- Replaced packed bit mapping with `BitCoordinate` dictionary.
- Added mapping verification tests.

Phase 4: Macro Cancellation & Non-Blocking Taps (Partial)
- Added cancellation token to `MacroEngine`.
- Delay slicing implemented for cancellation responsiveness (non-blocking async scheduling still pending).
- Added macro cancellation tests.

Phase 5: Polish & Logging Rotation
- Add optional log rotation or append mode.
- Cache Accessibility trust result with TTL.
- Document changes in README & IMPLEMENTATION.

Phase 6: Deferred Enhancements (Optional / separate branch)
- JSON mapping externalization, CLI tooling.

## Interfaces (Draft Contracts)
`protocol RawReportParser { func parse(bytes: [UInt8]) -> [GKeyStateChange] }`
`struct GKeyStateChange { let gKey: Int; let down: Bool }`

`enum KeyboardAction { case keyTap(String); case keyDown(String); case keyUp(String); case macro(String) }`
`final class KeyboardActionExecutor { func perform(_ action: KeyboardAction, completion: ((Result<Void, Error>) -> Void)?) -> Result<Void, Error> }`
Note: Uses string keys resolved via `VirtualKeyboard.keyCodeFromString`; future improvement could adopt strongly-typed `KeyCode` in emitted actions once mapping centralization is complete.

`enum LogLevel: Int { case debug=0, info, warn, error }`
Environment: `G13_LOG_LEVEL` or default `.info`.

`struct BitCoordinate { let byte: Int; let bit: Int }`
Mapping: `[BitCoordinate: Int /* gKey */]` plus reverse lookup validation.

## Acceptance Criteria (Per Phase) (Progress Noted)
Phase 1 (Met):
- All tests pass; parser tests cover single key down, multiple changes, no change -> empty array.
- `HIDDevice` removed raw bit iteration logic.

Phase 2 (Partial):
- `KeyMapper` emits actions; executor invokes underlying output.
- Executor tests assert macro and tap translation.
- Pending: enrich error taxonomy (creation vs send vs entitlement) and integrate.

Phase 3 (Met):
- Single config read verified (search for multiple `readConfig` calls removed).
- Mapping struct present; tests enumerate mapping completeness (22 G keys mapped) plus uniqueness.

Phase 4 (Partial):
- Macro cancellation stops execution mid-delay/text (token tested).
- Tap operation still uses direct `usleep`; scheduling refactor outstanding.

Phase 5:
- Log rotation/appending controllable via env var `G13_LOG_APPEND=true`.
- Accessibility trust cached with TTL reducing repeated system calls (>50%).

## Metrics & Observability
-- Test count increase: +6 new test files (parser, executor, mapping, cancellation) since baseline.
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

## Task Checklist (Detailed) (Updated Status Inline)
- [ ] Phase 0 baseline metrics script (optional)
- [x] Add `LogLevel` enum and filtering logic in `Logger.swift`
- [x] Inject log level from env
- [x] Introduce `RawReportParser.swift`
- [x] Move parsing code from `HIDDevice` to parser
- [x] Add `G13VendorReportParserTests.swift`
- [x] Add `KeyboardAction` enum file
- [x] Implement `KeyboardActionExecutor.swift`
- [x] Refactor `KeyMapper` to emit actions
- [x] Add executor tests
- [ ] Expand error enums in keyboard outputs
- [x] Config centralization (single load, pass references)
- [x] Replace packed bit mapping with struct dictionary
- [x] Mapping tests (complete coverage, reverse validation)
- [x] Add cancellation token to `MacroEngine`
- [ ] Async tap scheduling
- [x] Macro cancellation tests
- [ ] Logger size rotation (append mode done)
- [ ] Accessibility trust caching
- [ ] Documentation updates (README, IMPLEMENTATION, KEYBOARD-OUTPUT-MODES)
- [ ] Remove deprecated feature flag references (legacy parsing already removed)

## Testing Additions Summary (Current State)
- Added: `G13VendorReportParserTests.swift`, `KeyboardActionExecutorTests.swift`.
- Pending: `MappingTableTests.swift`, `MacroCancellationTests.swift`.

## Open Questions
- Should macro cancellation abort currently pressed keys or leave them for caller cleanup?
- Do we need configurable tap delay beyond static 10ms? (Could make it part of config.)
- Is log rotation size threshold environment configurable (e.g. `G13_LOG_MAX_BYTES`)?

## Next Step (Upon Merging Plan)
Begin Phase 1 implementation; ensure green tests then proceed sequentially.
