Type: research
Status: resolved
Blocked by:

## Question

Using first-party Apple documentation and minimal experiments where necessary, which supported macOS mechanisms can detect a system-wide drag containing exactly one HEIC file early enough to show a transient Drop Zone beneath Dropshot's menu-bar item, and what constraints apply across applications, Spaces, full-screen windows, displays, sandboxing, accessibility permission, and drag cancellation?

## Comments

Research artifact: `../research/drag-observation-and-drop-zone-mechanism.md`

## Answer

Use permission-free global-plus-local AppKit mouse event monitors to notice dragging, inspect the named drag pasteboard for an early one-HEIC signal, and show a nonactivating `NSPanel` registered as the definitive file-URL/file-promise destination. Anchor it to the live status-item button; configure it to join Spaces and full-screen apps; derive Option state from mouse-event/current modifier flags; and dismiss via mouse-up, destination lifecycle callbacks, button-state polling, and a stale timeout. The drop can work in App Sandbox when URLs/promises are used.

Apple does not explicitly guarantee reliable inspection of another app's drag pasteboard before Dropshot becomes a destination. A signed compatibility spike on both target macOS releases—especially Messages, Escape cancellation, multi-display/full-screen behavior, and sandboxed URL/promise access—is therefore release-blocking. Full findings and citations: [Drag observation and Drop Zone mechanism](../research/drag-observation-and-drop-zone-mechanism.md).
