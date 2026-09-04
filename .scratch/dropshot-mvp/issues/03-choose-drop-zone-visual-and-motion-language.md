Type: prototype
Status: resolved
Assignee: Codex
Blocked by: 01

## Question

What Drop Zone layout, size, placement, copy, visual states, and motion make eligibility, JPEG default, live Option-to-PNG override, successful copying, failure, and drag cancellation immediately understandable while still feeling native to macOS?

## Comments

Reaction artifact: [`../prototypes/drop-zone-visual-language.html`](../prototypes/drop-zone-visual-language.html) (throwaway UI prototype; open directly in a browser and use `?variant=A`, `B`, or `C`).

## Answer

Use the compact, arrowless **Format Orb**: approximately 202 × 170 points, centered eight points beneath the status item and horizontally clamped to the visible screen. It contains a circular target above three short lines and never shows the filename.

For Default Conversion, show “Drop HEIC here,” “Release to copy as JPEG,” and “Hold ⌥ for PNG.” While Option is held, retain the title, change the subtitle to “Release to copy as PNG,” replace the footer with “Release ⌥ for JPEG,” and apply a restrained accent-color change. The footer is passive text, not a segmented control or clickable toggle.

Enter over 160–180 ms by fading and scaling from 96% to 100%, anchored beneath the menu-bar item. Reduced Motion uses opacity only. Cancellation silently reverses the entrance immediately. On success, turn the ring into a checkmark and show “Copied,” “Ready to paste,” and “Copied as JPEG” or “Copied as PNG” for 800 ms. On failure, turn the ring into an exclamation mark and show “Couldn’t Convert,” “Open Dropshot for details,” and “Original unchanged” for three seconds. A new drag may replace either terminal state immediately.
