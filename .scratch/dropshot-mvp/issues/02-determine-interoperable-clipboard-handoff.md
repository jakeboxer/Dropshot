Type: research
Status: resolved
Blocked by:

## Question

Using first-party platform documentation and targeted compatibility experiments, which NSPasteboard representations should a Clipboard Handoff publish so converted JPEG and PNG content pastes reliably into Messages, Mail, Preview, ChatGPT, Claude, and common browser text areas without creating a user-visible permanent file?

## Comments

Research artifact: `../research/interoperable-clipboard-handoff.md`

## Answer

Publish one pasteboard item containing exact JPEG or PNG bytes under the corresponding UTI, plus TIFF data as an AppKit fallback. Prepare all representations before clearing the general pasteboard. Do not use a temporary file URL, legacy file contents, or a file promise in the baseline; raw image data intentionally wins over filename semantics. Because receiving apps choose their own supported representations, the named target-app matrix is a release gate, with file promises considered only if measured failures justify them.

Full findings and citations: [Interoperable Clipboard Handoff](../research/interoperable-clipboard-handoff.md)
