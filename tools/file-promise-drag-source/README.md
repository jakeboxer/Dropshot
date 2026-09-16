# Dropshot drag source

This development-only AppKit executable starts real file-URL and file-promise drag sessions for Dropshot's live drag checks. It is compiled independently with `swiftc`; it is not part of the Dropshot Xcode project or shipped app.

The build ad-hoc signs and verifies the complete helper bundle. It copies the checked-in `DropshotTests/Fixtures/oriented-metadata.heic` fixture into the helper's resources without changing its bytes. The file-URL card uses AppKit’s standard `NSURL` pasteboard writer. Dropshot detects its HEIC content type through metadata before release. The promise card advertises `public.heic` through `NSFilePromiseProvider` and copies that fixture only when the destination requests delivery. The source fixture is never changed.

## Build and run

From the repository root:

```sh
tools/file-promise-drag-source/build.sh
open tools/file-promise-drag-source/build/DropshotDragSource.app
```

To keep the diagnostic log visible or pass another readable HEIC path, run the bundle executable directly:

```sh
tools/file-promise-drag-source/build/DropshotDragSource.app/Contents/MacOS/DropshotDragSource \
  DropshotTests/Fixtures/12-megapixel.heic
```

The helper prints the fixture's SHA-256, drag kind, and final drag operation. A real promise receipt also prints `Promise requested` and `Promise delivered` with the destination path. Those messages distinguish live `NSFilePromiseReceiver` fulfillment from a file-URL drag or named-pasteboard simulation.

## Exercise Dropshot

1. Build and launch the Dropshot app under test, then launch this helper from Terminal so its promise-delivery messages remain visible.
2. Drag the **File URL** card onto Dropshot's Drop Zone and release it. Leave Option released to request the Default Conversion to JPEG.
3. Click **Inspect Clipboard and Promise Cleanup**. Confirm `Items: 1`, `JPEG: true`, `PNG: false`, and `TIFF: true`, then paste into an image-aware destination.
4. Repeat while physically holding Option before release. Confirm one item reports PNG and TIFF, not JPEG, and confirm the approved success feedback. The helper does not synthesize modifier state.
5. Repeat steps 2–4 with the **File Promise** card. Confirm the helper prints both promise messages and that the destination path is a unique Dropshot-owned operation directory.
6. After each promised conversion completes, click the inspection button and confirm `Promise input exists: false`, `Operation directory exists: false`, and `Fixture unchanged: true`. The displayed path is the unique Dropshot-owned operation directory that received the promise. The helper also prints the fixture SHA-256 at launch; the bundled default must match `shasum -a 256 DropshotTests/Fixtures/oriented-metadata.heic`.

For each test, click **Inspect Clipboard and Promise Cleanup** before **Copy Results** because copying the captured report replaces the clipboard image. The copied report includes the inspection number, pasteboard change count, and last drag status. You can also select report text and press Command-C.

The source app proves that AppKit requested and received a real file promise. Dropshot remains responsible for validating the delivered input, removing its Ephemeral Input, publishing the requested representation plus TIFF as exactly one pasteboard item, and showing success only after the Clipboard Handoff succeeds.
