Type: task
Status: resolved
Assignee: Codex
Blocked by: 01, 02

## Question

Build and run the smallest signed compatibility harness needed to verify the two research assumptions that Apple documentation cannot guarantee: that Dropshot can identify a single HEIC drag from Messages before it enters the Drop Zone, and that the proposed JPEG/PNG-plus-TIFF Clipboard Handoff pastes correctly into the required receiver matrix. Exercise both target macOS releases where available, record the repeatable procedure and evidence, identify which checks can be automated, and report any constraints that the architecture decision must absorb.

## Comments

Compatibility harness, repeatable procedure, and evidence matrix: [`../compatibility/drag-and-clipboard-spike.md`](../compatibility/drag-and-clipboard-spike.md). Automated representation checks pass. A real Messages drag passes on macOS 26.6.2: one HEIC file URL and `public.heic` were visible before destination entry and caused the Drop Zone to appear; destination metadata matched. JPEG-plus-TIFF and PNG-plus-TIFF both pass in Messages, Superhuman Mail, Apple Mail, Preview, the ChatGPT and Claude apps, ChatGPT in Safari, and Claude in Chrome. The preceding macOS release was unavailable.

## Answer

On macOS 26.6.2, a permission-free global AppKit drag monitor identified a single Messages HEIC before destination entry from one `public.file-url` item carrying explicit `public.heic`; this caused the Drop Zone to appear, and destination entry/drop exposed the same item and representations. No file-promise materialization was needed in the observed Messages case.

One-item JPEG-plus-TIFF and PNG-plus-TIFF Clipboard Handoffs both succeeded in Messages, Superhuman Mail, Apple Mail, Preview, the native ChatGPT and Claude apps, ChatGPT in Safari, and Claude in Chrome. This validates the combined representation strategy across the required available receiver matrix, while leaving TIFF's independent necessity unproven because receivers do not disclose which offered representation they consumed.

The architecture must treat pre-destination inspection as a fallible adapter, make destination-time classification authoritative, preserve an indeterminate early state and sanitized raw-type diagnostics, prepare all clipboard representations eagerly before one atomic publication, and retain real-system checks as a release gate. The preceding supported macOS release was unavailable and remains a required release-machine check. Full procedure and evidence: [Drag and Clipboard Compatibility Spike](../compatibility/drag-and-clipboard-spike.md).
