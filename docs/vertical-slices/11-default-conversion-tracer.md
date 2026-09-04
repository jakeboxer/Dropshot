# Vertical Slice #11: Default Conversion tracer

## Public seam and behavior

`DropCoordinator.accept(_:)` is the public-behavior seam. Given an Accepted Drop, it drives the pure `DropWorkflow` and injected test adapters. The observed behavior is one JPEG conversion request followed by one Clipboard Handoff containing the converted JPEG and TIFF representations, both tagged with the same Drop ID.

## Failing test

Test: `DropCoordinatorTests.acceptedDropPerformsDefaultConversionAndClipboardHandoff`

Initial focused run failed during compilation with the expected missing production contracts, including:

```text
error: cannot find type 'ImageConverting' in scope
error: cannot find type 'ConversionRequest' in scope
error: cannot find type 'ClipboardPublishing' in scope
error: cannot find type 'ClipboardHandoff' in scope
** TEST FAILED **
```

## Minimum production change

- Added domain values for Accepted Drops, ID-tagged conversion requests, converted representations, and Clipboard Handoffs.
- Added `DropWorkflow`, which owns the active Drop ID and emits declarative conversion and Clipboard Handoff effects.
- Added the main-actor `DropCoordinator`, which executes effects through injected conversion and clipboard adapters and returns conversion results to the workflow.

No AppKit conversion or pasteboard implementation is part of this tracer.

## Focused passing output

Command:

```sh
xcodebuild test -quiet \
  -project Dropshot.xcodeproj \
  -scheme Dropshot \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/DropshotDerivedData \
  -only-testing:DropshotTests/DropCoordinatorTests/acceptedDropPerformsDefaultConversionAndClipboardHandoff \
  CODE_SIGNING_ALLOWED=NO
```

Result: exited 0. After review fixes, the final focused run completed in 0.943 seconds.

## Complete relevant suite

Command:

```sh
xcodebuild test -quiet \
  -project Dropshot.xcodeproj \
  -scheme Dropshot \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/DropshotDerivedDataSigned
```

Result: exited 0. The `DropCoordinatorTests` tracer and all four existing UI-test executions passed; the final run completed in 24.262 seconds.

## Performance evidence

Not required for this seam-only tracer; it introduces no production conversion implementation or measured user-facing timing path.
