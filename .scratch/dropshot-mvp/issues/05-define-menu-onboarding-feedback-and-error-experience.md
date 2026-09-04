Type: prototype
Status: resolved
Assignee: Codex
Blocked by:

## Question

What exact first-launch guidance and persistent menu states should explain Dropshot, opt-in launch at login, sound behavior, status/help, About, Quit, and the session-scoped Last Error with Copy Details?

## Comments

Reaction artifact: [`../prototypes/menu-onboarding-error-experience.html?variant=B`](../prototypes/menu-onboarding-error-experience.html?variant=B) (throwaway UI prototype; Variant B, Centered Welcome, selected).

## Answer

On first launch, show a one-time menu-attached popover using the centered visual language of the Drop Zone. Its title is “Drag an HEIC image to convert.” Its body says: “Drag an HEIC image from any app. Drop it into Dropshot to copy a JPEG, ready to paste. Hold ⌥ while dragging to copy a PNG instead.” It includes an unchecked “Launch Dropshot at Login” checkbox and a primary “Got It” button. The guidance is purely explanatory: there is no required practice drag. Clicking outside or choosing “Got It” dismisses and completes onboarding. “How to Use Dropshot…” reopens the same guidance later.

Keep the persistent menu compact. Show a disabled “Ready for an HEIC drag” status row, then “How to Use Dropshot…”, a conditional “Last Error” submenu, checked or unchecked “Play Sounds” and “Launch Dropshot at Login” items, followed by “About Dropshot” and “Quit Dropshot.” Launch at login remains opt-in. “Play Sounds” defaults on and governs restrained, distinct success and failure effects only; it never suppresses VoiceOver announcements.

Show “Last Error” only after a failed Clipboard Handoff. Its submenu contains a short human-readable summary and “Copy Details.” Opening the submenu or copying its details does not clear it. Clear it after the next successful Clipboard Handoff or when Dropshot restarts; keep no history. Copied details are stable plain text containing Dropshot version/build, macOS version, timestamp, requested output format, failure stage, and a sanitized error code and message. Exclude filenames, paths, clipboard contents, image pixels, source metadata, and stack traces.

VoiceOver announces the Drop Zone, live output-format changes, success, and failure independently of the sound preference. Reduced Motion follows the macOS accessibility setting.
