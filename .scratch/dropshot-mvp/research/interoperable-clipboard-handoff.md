# Interoperable Clipboard Handoff

## Decision

The MVP should publish **one `NSPasteboardItem`** to `NSPasteboard.general` with these representations, in this preference order:

1. The exact converted bytes under the output format's UTI:
   - JPEG: `NSPasteboard.PasteboardType(UTType.jpeg.identifier)` (`public.jpeg`)
   - PNG: `NSPasteboard.PasteboardType.png` (`public.png`)
2. A `NSPasteboard.PasteboardType.tiff` fallback generated from the same normalized image.

Prepare the conversion and every representation in memory before touching the general pasteboard. Only after all preparation succeeds, call `clearContents()` and `writeObjects([item])`. Apple defines the general pasteboard as the shared transfer mechanism, supports `NSPasteboardWriting` objects and multiple representations, and says clearing is the first step in replacing its contents. This ordering is what lets Dropshot preserve the existing clipboard on any conversion/preparation failure. [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard) · [clearContents()](https://developer.apple.com/documentation/appkit/nspasteboard/clearcontents%28%29) · [NSPasteboardItem](https://developer.apple.com/documentation/appkit/nspasteboarditem)

Do **not** include a file URL, legacy file-contents representation, or file promise in the baseline handoff. A raw image item has no portable filename metadata, so the MVP should prefer a reliable inline image over the weaker requirement for a named attachment.

## Rationale

Apple defines JPEG and PNG as system image types usable for in-memory transfer, including pasteboard transfer; AppKit also exposes PNG explicitly as a standard pasteboard type. [Uniform Type Identifiers](https://developer.apple.com/documentation/uniformtypeidentifiers/) · [UTTypeJPEG](https://developer.apple.com/documentation/uniformtypeidentifiers/uttypejpeg) · [NSPasteboardTypePNG](https://developer.apple.com/documentation/appkit/nspasteboard/pasteboardtype/png)

Publishing the actual requested encoding matters because OpenAI documents clipboard image paste in ChatGPT and lists JPEG and PNG as supported input formats. This is first-party support for the direct encoded representation, though it does not document AppKit type-selection behavior. [ChatGPT Image Inputs FAQ](https://help.openai.com/en/articles/8400551-chatgpt-image-inputs-faq)

TIFF is the native AppKit compatibility fallback: `NSImage` conforms to `NSPasteboardWriting`, AppKit exposes TIFF as a standard pasteboard type, and `NSImage` supports pasteboard initialization. It is an additional representation of the same logical image, not a second pasteboard item. [NSPasteboardWriting](https://developer.apple.com/documentation/appkit/nspasteboardwriting) · [init(pasteboard:)](https://developer.apple.com/documentation/appkit/nsimage/init%28pasteboard%3A%29)

`NSPasteboardTypeFileURL` represents a URL to a real file. Using it would require an on-disk temporary file that must remain readable for an unknown consumer lifetime; cleanup would therefore be externally observable and potentially racy. The lifetime conclusion is an inference from the file-URL contract, not an Apple guarantee. [NSPasteboard file URL type](https://developer.apple.com/documentation/appkit/nspasteboard/pasteboardtype/fileurl) · [System-declared UTIs](https://developer.apple.com/documentation/uniformtypeidentifiers/system-declared-uniform-type-identifiers)

`NSFilePromiseProvider` can advertise a type and filename and materialize a file only when a receiver requests it, so it is worth testing later as a named-attachment fallback. Apple's documentation and sample focus on drag-and-drop receivers and do not establish that Messages, Mail, Preview, ChatGPT, Claude, or browser editors consume file promises from the general pasteboard. It must not be treated as compatible without experiments. [NSFilePromiseProvider](https://developer.apple.com/documentation/appkit/nsfilepromiseprovider) · [Supporting Drag and Drop Through File Promises](https://developer.apple.com/documentation/appkit/supporting-drag-and-drop-through-file-promises)

Legacy file-content pasteboard APIs are not a suitable compatibility layer; Apple directs modern clients to use the file's UTI to represent its contents. [NSPasteboard fileContents](https://developer.apple.com/documentation/appkit/nspasteboard/pasteboardtype/filecontents)

## Compatibility evidence and limits

Apple explicitly says each receiving app decides what it can paste. Apple confirms that Preview can paste clipboard contents into an image, while its Mail documentation describes image/file attachment behavior without specifying accepted pasteboard types. OpenAI confirms direct clipboard image paste for ChatGPT. No first-party Anthropic documentation was found that specifies Claude's accepted macOS pasteboard types. Therefore documentation cannot prove the requested receiver matrix; the exact compatibility claim must be an MVP release gate verified on both supported macOS versions. [How to copy and paste on Mac](https://support.apple.com/en-us/102553) · [Preview keyboard shortcuts](https://support.apple.com/en-au/guide/preview/cpprvw0003/11.0/mac/26) · [Send attachments in Mail on Mac](https://support.apple.com/guide/mail/mlhlp1050/mac) · [ChatGPT Image Inputs FAQ](https://help.openai.com/en/articles/8400551-chatgpt-image-inputs-faq)

## Required acceptance matrix

Test JPEG+TIFF and PNG+TIFF payloads in:

- Messages compose
- Mail compose
- Preview
- ChatGPT macOS and chatgpt.com
- Claude desktop and claude.ai
- Safari and Chrome content-editable/file-aware text areas representative of common browser apps

For every receiver and output format, record:

- whether Paste is enabled and completes;
- whether the result is an inline image, attachment, or nothing;
- whether dimensions, orientation, color appearance, and (for PNG) alpha survive;
- whether the receiver preserves the requested JPEG/PNG encoding;
- whether pasting still works after Dropshot quits.

Passing means the receiver obtains one visually correct image, never duplicate representations. The app-specific results should be recorded with app and OS version because Apple leaves representation selection to each receiver. [How to copy and paste on Mac](https://support.apple.com/en-us/102553)

If a required receiver fails the baseline, test—in this order—direct format bytes without TIFF, then `NSFilePromiseProvider` alone, then a combined direct-data/file-promise payload. Promote a fallback only for evidence from the complete matrix. Do not add a temporary file URL unless the product explicitly accepts an on-disk lifetime and cleanup policy.

## Implementation sketch

```swift
let item = NSPasteboardItem()
let primaryType = NSPasteboard.PasteboardType(outputUTType.identifier)

guard item.setData(encodedOutput, forType: primaryType),
      item.setData(tiffFallback, forType: .tiff) else {
    throw ClipboardHandoffError.couldNotPrepareRepresentations
}

let pasteboard = NSPasteboard.general
pasteboard.clearContents()
guard pasteboard.writeObjects([item]) else {
    throw ClipboardHandoffError.writeFailed
}
```

The concrete implementation should preserve the old clipboard through the preparation phase. AppKit does not provide a transactional rollback after `clearContents()`, so a rare final write failure can still leave the clipboard cleared; the UI/error contract should describe this precisely rather than promise an impossible atomic replacement. The lack of rollback is an inference from Apple's separate clear/write API contract. [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard) · [clearContents()](https://developer.apple.com/documentation/appkit/nspasteboard/clearcontents%28%29)
