# Drag and Clipboard Compatibility Spike

## Harness

For this spike, a temporary compatibility harness was built into the Dropshot menu-bar app. Its **Compatibility Harness** submenu could:

- show an in-memory timestamped report;
- show a registered nonactivating test Drop Zone;
- publish a generated JPEG plus TIFF as one pasteboard item; and
- publish a generated PNG plus TIFF as one pasteboard item.

During every global or local `leftMouseDragged` event, the harness inspected the named drag pasteboard before Dropshot became the destination. It recorded item count, file URLs, HEIC/HEIF and promise-related types, and all advertised pasteboard types. When it saw one HEIC file URL or a relevant promised/HEIC type, it automatically showed the Drop Zone. The registered destination separately recorded the types visible on entry and drop. The harness remains available for the required check on the preceding macOS release and should be removed before MVP implementation begins.

Build and launch:

```sh
xcodebuild build \
  -project Dropshot.xcodeproj \
  -scheme Dropshot \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/DropshotHarnessDerivedData \
  CODE_SIGNING_ALLOWED=YES

open /tmp/DropshotHarnessDerivedData/Build/Products/Debug/Dropshot.app
```

The build is ad-hoc signed as `com.jakeboxer.Dropshot`. This proves a signed local-development harness, not Developer ID distribution or notarization.

## Automated evidence

On macOS 26.6.2 (build 25G83), Xcode 26.6:

- app build: passed;
- strict deep code-signature verification: passed;
- unit checks: passed for both JPEG and PNG;
- each unit check verified exactly one pasteboard item with exact primary-format bytes and TIFF fallback bytes, and no extra declared representation.

Run only the automated checks with:

```sh
xcodebuild test \
  -project Dropshot.xcodeproj \
  -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:DropshotTests
```

Automatable in the eventual MVP: drag-classifier decisions given captured pasteboard descriptors; item-count and UTI classification; exact encoded bytes; one-item clipboard publication; declared representation set; panel state transitions; stale timeout and cancellation fallback logic.

Not stable to automate as ordinary unit/UI tests: another process's pre-destination drag metadata, real Messages file promises, cross-Space/full-screen window behavior, multi-display placement, Escape cancellation delivery, and receiver-specific paste interpretation.

## Messages drag evidence

On macOS 26.6.2 (build 25G83), a drag of `IMG_2629.heic` from Messages produced a global-monitor observation at 03:04:22Z, caused the compatibility Drop Zone to appear, entered that destination at 03:04:30Z, and was dropped at 03:04:32Z.

The pre-destination observation contained exactly one pasteboard item, a `public.file-url` ending in `.heic`, and an explicit `public.heic` representation. The complete advertised representation set was:

```text
com.apple.UIKit.private.drag-suggested-name
com.apple.uikit.private.drag-item
public.file-url
public.heic
public.jpeg
public.png
public.url
```

The destination reported the same one item and the same representation set on both entry and drop. For this Messages/macOS combination, Dropshot can therefore classify an Eligible Drag before destination entry without materializing a file promise. The evidence establishes observed compatibility, not a documented platform guarantee; the classifier must still handle unavailable or indeterminate metadata on other OS/app versions.

## Clipboard receiver evidence

On macOS 26.6.2, both the one-item JPEG-plus-TIFF payload and the one-item PNG-plus-TIFF payload pasted successfully into every tested receiver:

- Messages;
- Superhuman Mail;
- Preview, using **File → New from Clipboard**;
- the native ChatGPT app;
- the native Claude app;
- ChatGPT's image-capable web composer in Safari; and
- Claude's image-capable web composer in Chrome.

These results validate the proposed combined representations for this OS/app matrix. They do not reveal which representation each receiver selected, so they do not independently establish whether the TIFF fallback is necessary. Superhuman Mail and Apple Mail were tested as distinct receivers.

## Manual procedure and evidence matrix

Use a known single HEIC image in Messages. Open **Compatibility Harness → Show Report** before each run.

1. Drag the image within Messages without crossing the test Drop Zone. Record whether a `Pre-destination observation` appears, whether it reports exactly one item, and whether it exposes a HEIC file URL or a promise/content type sufficient to identify HEIC.
2. Repeat and move over the automatically shown Drop Zone. Record the destination `entered` types, then cancel with Escape and confirm the source remains unchanged.
3. Repeat and drop. Record the destination `dropped` types and whether URL or file-promise materialization would be required.
4. Repeat on the primary display, a secondary display if available, another Space, and with Messages full screen. Record whether the Drop Zone becomes visible on the active display and Space.
5. Choose **Publish JPEG + TIFF**, paste once into each receiver, and record whether the result is an inline visible image rather than a filename, attachment placeholder, or failure.
6. Repeat with **Publish PNG + TIFF**. Confirm the blue square with white circle is visibly correct.

| OS | Source/receiver | JPEG + TIFF | PNG + TIFF | Evidence/notes |
|---|---|---:|---:|---|
| macOS 26.6.2 | Messages pre-destination drag | pass | n/a | One item; HEIC file URL and `public.heic` visible eight seconds before destination entry; Drop Zone appeared automatically; destination types matched |
| macOS 26.6.2 | Messages | pass | pass | Both payloads accepted |
| macOS 26.6.2 | Superhuman Mail | pass | pass | Both payloads accepted; not Apple Mail |
| macOS 26.6.2 | Apple Mail | pass | pass | Both payloads accepted |
| macOS 26.6.2 | Preview | pass | pass | Both accepted through **File → New from Clipboard** |
| macOS 26.6.2 | ChatGPT app | pass | pass | Both payloads accepted |
| macOS 26.6.2 | Claude app | pass | pass | Both payloads accepted |
| macOS 26.6.2 | Safari / ChatGPT web composer | pass | pass | Both payloads accepted |
| macOS 26.6.2 | Chrome / Claude web composer | pass | pass | Both payloads accepted |
| preceding supported macOS | Messages pre-destination drag | unavailable | n/a | Requires a physical or virtual test Mac |
| preceding supported macOS | receiver matrix above | unavailable | unavailable | Requires a physical or virtual test Mac |

## Architecture constraints

- Treat pre-destination drag inspection as a fallible adapter, never as a guaranteed domain fact.
- Keep destination-time classification authoritative and model an indeterminate pre-destination state.
- On the tested Messages/macOS 26.6.2 combination, use the single `public.file-url` plus explicit `public.heic` representation for early classification; no file-promise path is needed for that case.
- Preserve raw advertised type identifiers in sanitized diagnostic output so OS/app regressions are actionable.
- Keep clipboard publication behind an adapter that writes one eagerly prepared item atomically.
- Do not add filename/file-URL or file-promise clipboard representations unless a measured receiver failure requires them.
- JPEG/PNG plus TIFF is accepted by every tested receiver on macOS 26.6.2; because combined-payload testing cannot show which representation was consumed, TIFF's necessity remains unproven.
- Keep real-system compatibility checks as a release gate on each supported macOS major release.
