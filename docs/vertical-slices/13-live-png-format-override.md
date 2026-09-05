# Vertical Slice #13: live PNG Format Override

## Public seams and behavior

Issue #1 pre-agrees `FormatSelection`, `DropWorkflow`, and `ImageConversion` as the format-mapping, interaction, and pixel-correctness seams. Issue #13 supplies this slice's acceptance criteria.

`FormatSelection.resolve(optionHeld:)` selects JPEG by default and PNG while Option is held. Modifier events synchronously update `DropWorkflow.selectedFormat`, exposed through the main-actor coordinator. `AcceptedDrop` carries destination-time Option evidence; it overrides earlier observations and fixes the format in the conversion request. Later modifier changes cannot change that request or its Clipboard Handoff.

PNG uses the existing primary-still, orientation, full-resolution, 8-bit SDR sRGB pipeline with a transparent premultiplied raster instead of JPEG's white background. Fresh PNG and lossless LZW TIFF encodings preserve alpha and discard source metadata. No AppKit modifier monitoring or rendered Drop Zone is introduced here; those platform/presentation adapters remain later slices.

## Red → green evidence

Each behavior was added vertically before its implementation:

1. `FormatSelectionTests/optionSelectsPNGUntilReleased`: compilation failed with `Cannot find 'FormatSelection' in scope`; adding the mapping made the focused test pass.
2. `DropWorkflowTests/modifierChangesImmediatelyUpdatePresentationFormat`: compilation failed for missing `selectedFormat` and `modifiersChanged`; adding synchronous state/event handling made the focused suite pass.
3. `DropWorkflowTests/authoritativeDropOverridesEarlierModifierObservation`: compilation failed with `Extra argument 'optionHeld' in call`; carrying authoritative evidence in Accepted Drop and resolving it when accepting made both Option-held and released cases pass.
4. `ImageConversionTests/formatOverridePreservesAlphaInPNGAndTIFFFallback`: the test failed while the converter rejected PNG; enabling PNG encoding and alpha-preserving rasterization made the image suite pass.
5. `DropCoordinatorTests/optionHeldAcceptedDropHandsOffRealPNGAndTIFF`: compilation failed for missing coordinator modifier/state access; forwarding those to the workflow made the focused unit suite pass, including real conversion and handoff to the clipboard test adapter.

The first sandboxed test launch could not contact `com.apple.testmanagerd.control`; subsequent tests used the required test-runner access. A method-filtered invocation selected no Swift Testing cases and is not counted as evidence; the containing suite was then run and demonstrated the PNG test failure. Temporary logs from the initial focused runs were lost across the interrupted session; the observed outcomes above were retained in task history. The full suite was run after resumption.

Shared conversion tests now exercise both JPEG and PNG for all eight orientations, dimensions, primary-image selection, metadata/auxiliary stripping, unchanged input, no output files, independently owned representations after input deletion, and deterministic repeated bytes. Alpha expectations use the existing analytical transparency fixture, including partially transparent red. Fixture provenance and pixel tolerances remain in `DropshotTests/Fixtures/README.md`.

## Complete suite and typechecking

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Dropshot13
```

Result: exit 0 on 2026-09-04; testing elapsed 30.353 seconds. Unit cases and all UI smoke/launch tests passed. Each focused/full invocation compiled and typechecked the application and tests. The first full build exposed two Swift concurrency warnings in workflow effect comparisons. Marking the immutable, Sendable `DropWorkflow.Effect` enum explicitly nonisolated removes actor isolation from its Equatable conformance; the full suite was rerun after this correction: exit 0, 18.105 seconds, no compiler warnings or test failures. The standards reviewer also approved this delta.

## Focused performance evidence

Measured on macOS 26.6.2 (25G83), Apple M1 Max with 32 GB RAM, using the existing 4000 × 3000 synthetic HEIC and optimized production converter:

```sh
swiftc -O -parse-as-library -module-cache-path /tmp/DropshotModuleCache \
  Dropshot/Domain/DropModels.swift Dropshot/Domain/FormatSelection.swift \
  Dropshot/Workflow/DropWorkflow.swift Dropshot/Workflow/DropCoordinator.swift \
  Dropshot/Conversion/ImageConversion.swift scripts/measure-image-conversion.swift \
  -o /tmp/measure-image-conversion13
/usr/bin/time -l /tmp/measure-image-conversion13 \
  DropshotTests/Fixtures/12-megapixel.heic png
```

The unrestricted measurement exited successfully: warm-up 0.647 seconds; five runs 0.528, 0.533, 0.503, 0.530, and 0.534 seconds. PNG was 221,458 bytes; TIFF was 305,992 bytes. Maximum resident set size was 408,649,728 bytes; peak memory footprint was 161,219,520 bytes. These are whole-process measures, not additional memory relative to an app baseline. They do not establish the release gate of less than 300 MB additional peak memory; the resident metric exceeds 300 MB and needs release-level measurement. An earlier sandboxed run could not collect resource metrics and is excluded.

This converter-only synthetic benchmark does not establish rendered format feedback timing, end-to-end Clipboard Handoff latency, photographic/HDR performance, or Release Artifact readiness. The broader fixture and real receiver checks recorded in slice #12 remain release gates.

## Review

Two independent code-review agents inspected `git diff --cached b84e024d986ff3734faa109a3f983bbf8868a2cd` before commit. Standards: no documented violations or actionable smell findings. Spec: no missing requirements, incorrect behavior, or scope creep within issue #13. UI/drop destination adapter integration remains deferred to its own slices.
