Label: wayfinder:map

## Destination

An implementation-ready product and technical specification for a locally runnable, code-signed Dropshot MVP on Apple silicon, targeting the newest supported macOS release and the preceding major release.

## Notes

Dropshot is a native macOS menu-bar utility. Consult the `grilling` and `domain-modeling` skills whenever resolving product decisions, and keep `CONTEXT.md` synchronized with settled domain language. Consult `codebase-design` and `tdd` when resolving architecture, test seams, and the validation contract.

Standing product constraints: an Eligible Drag may originate in any app; the Drop Zone appears automatically beneath the menu-bar item; Default Conversion produces JPEG; holding Option requests PNG; Clipboard Handoff creates no user-visible permanent file; launch at login is opt-in.

The implementation specification must require vertical red-green TDD at pre-agreed public seams: one failing behavior test, the minimum implementation to pass it, then the next slice. Automated tests must verify deterministic domain behavior and owned adapters wherever practical. Tests must observe public interfaces rather than private implementation details. Behaviors that require real macOS drag sessions, Spaces, full-screen windows, or third-party paste receivers must have explicit repeatable manual compatibility checks when stable automation is unavailable.

This map plans the MVP; implementation is not part of the effort.

## Decisions so far

- [Determine the supported drag-observation and Drop Zone mechanism](issues/01-determine-drag-observation-and-drop-zone-mechanism.md): Use mouse-only global/local AppKit monitors plus early drag-pasteboard inspection to summon a nonactivating registered drop panel; validate Messages' pre-destination metadata and lifecycle behavior in a release-blocking compatibility spike.

- [Determine the interoperable Clipboard Handoff](issues/02-determine-interoperable-clipboard-handoff.md): publish one item with exact JPEG/PNG bytes plus TIFF fallback; defer filename/file-promise semantics unless the required receiver matrix proves they are needed.

- [Choose the Drop Zone visual and motion language](issues/03-choose-drop-zone-visual-and-motion-language.md): use a compact Format Orb with explicit release-to-copy format text, passive Option guidance, restrained format feedback, silent cancellation, and brief in-zone success or failure confirmation.
- [Run the drag and clipboard compatibility spike](issues/08-run-drag-and-clipboard-compatibility-spike.md): on macOS 26.6.2, Messages exposes a single HEIC file URL before destination entry, and one-item JPEG/PNG-plus-TIFF handoffs pass across the required available receiver matrix; retain fallible adapters and cross-version release checks.

## Not yet specified

- Packaging, signing, sandbox, entitlement, and deployment-target details that depend on the viable system interaction architecture.
- Exact automated-versus-manual conversion and clipboard acceptance criteria that depend on the selected interfaces, framework behavior, and compatibility findings.
- Any additional edge cases exposed by the interaction and clipboard prototypes.

## Out of scope

- Automatic JPEG-versus-PNG selection based on image content.
- Multiple-file and mixed-item drags.
- File-picker input or a permanently visible drop target.
- Conversion history, file management, and permanent converted files.
- App Store submission, analytics, accounts, subscriptions, and monetization.
- Intel Mac support.
