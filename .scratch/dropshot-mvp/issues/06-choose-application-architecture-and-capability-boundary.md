Type: grilling
Status: resolved
Assignee: Codex
Blocked by: 01, 02, 03, 04, 05, 08

## Question

Given the resolved interaction, conversion, clipboard, and compatibility contracts, which native macOS architecture and capability boundary should the MVP adopt, including framework choices, process lifecycle, state ownership, permissions, sandbox posture, and deployment target? Which deep modules, public interfaces, seams, and adapters let Codex verify drag classification, format selection, conversion, clipboard publication, and UI state transitions without coupling tests to AppKit implementation details?

## Answer

Build Dropshot as a single-process, agent-style AppKit application. Retain the explicit `NSApplicationDelegate` lifecycle and `LSUIElement`; use SwiftUI only as an optional way to implement declarative view content inside AppKit-owned presentation. Do not introduce an XPC helper, background daemon, framework target, or Swift package for the MVP. Keep one application target, one unit-test target, and the existing UI-test target, organized into Domain, Workflow, Conversion, PlatformAdapters, and Presentation source areas.

Run in App Sandbox without Accessibility or Input Monitoring permission. Request no broad filesystem capability. Obtain narrowly scoped read access only from a user drop, and balance any security-scoped access for the duration of the operation. Materialize file promises only inside a Dropshot-owned temporary-input directory, delete each materialized input after success, failure, or cancellation, and remove abandoned contents of that directory at launch. Persist no security-scoped bookmarks. The sandboxed build must pass the two-version compatibility gate; a sandbox exception requires a new explicit decision rather than an implicit entitlement expansion.

Target macOS 15.0 on Apple silicon and build against the newest macOS SDK. Support macOS 15 and 26. Any newer-OS enhancement must be availability-guarded and nonessential. Use ordinary Developer ID signing and notarization questions as a separate packaging decision; the architecture itself assumes a signed app and does not depend on App Store distribution.

One `@MainActor` application coordinator owns adapter lifetimes, the current interaction, Drop Zone presentation state, preferences, and session-scoped Last Error. Conversion executes asynchronously away from UI work and reports generation-tagged results back to that owner. Starting a new drag does not cancel an accepted conversion, but accepting a newer drop cancels or invalidates the earlier operation. Only the newest accepted drop may publish to the clipboard or produce terminal UI state.

The central deep module is `DropWorkflow`. Its interface accepts domain events—early drag observation, destination entry/update/exit/drop, modifier changes, timeout, and conversion completion—and returns the next state plus declarative effects. Effects request Drop Zone presentation, conversion, Clipboard Handoff, announcements, sounds, and Last Error changes. AppKit adapters execute effects; they do not own or independently infer workflow state.

Use these additional modules and seams:

- `DragClassifier` maps captured pasteboard descriptors to eligible, ineligible, or indeterminate without importing AppKit into domain logic. Early observation is fallible; destination-time classification is authoritative.
- `FormatSelection` maps modifier state to JPEG or PNG.
- `DroppedInput` exposes a scoped readable-source operation and owns URL access, file-promise materialization, cancellation, and cleanup. The converter never receives sandbox-lifetime responsibilities.
- `ImageConversion` applies the Conversion Policy and returns owned JPEG or PNG bytes plus TIFF fallback bytes, or a sanitized staged failure. Use Image I/O and Core Graphics for explicit decoding, raster handling, and encoding, with Core Image only where the system HDR-to-SDR rendering path is required. Do not use `NSImage` as the conversion model.
- `ClipboardPublication` eagerly publishes exactly one prepared pasteboard item atomically. It does not perform conversion or invent representations.
- `DropZonePresentation` renders workflow state without owning it.
- `ErrorSanitization` maps implementation failures into the privacy-safe Last Error contract.
- Clock, accessibility announcements, sounds, login-item registration, and preferences receive substitutable adapters only where production and deterministic test adapters both exist.

Persist onboarding completion and the sound preference with `UserDefaults`; manage opt-in login launch through `SMAppService.mainApp`. Keep active interaction state, Last Error, input data, and converted data in memory. Last Error remains session-scoped.

Pre-agree automated behavior tests at `DragClassifier`, `FormatSelection`, `DropWorkflow`, `ImageConversion`, `ClipboardPublication`, `ErrorSanitization`, and `DroppedInput`. Tests use public interfaces and in-memory adapters, not AppKit implementation details. Run adapter integration tests inside a signed sandboxed test host where deterministic. Real cross-application drag metadata, file-promise behavior, Spaces and full-screen presentation, multiple displays, Escape cancellation, and receiver-specific paste behavior remain repeatable manual release checks on both supported macOS major releases. Implementation must proceed as vertical red-green slices: one failing behavior test at an agreed seam, minimum production behavior, then the next slice.
