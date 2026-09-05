# Vertical Slice #12: real HEIC Default Conversion

## Public seam and behavior

Issue #1's Testing Decisions pre-agree `ImageConversion` as the pixel-correctness seam. Issue #12 supplies this slice's acceptance criteria. `ImageConversion.convert(_:)`, through the existing `ImageConverting` interface, now accepts a readable file URL and returns owned JPEG/TIFF representations. The caller remains responsible for source access lifetime. UI/drop destination and clipboard publication adapters belong to later slices.

## Red → green evidence

The first focused test, `defaultConversionPreservesOrientedVisibleImageAsOwnedRepresentations`, failed before production changes:

```text
Cannot find 'ImageConversion' in scope
Argument passed to call that takes no arguments
Testing cancelled because the build failed.
** TEST FAILED **
```

The minimum production change adds a URL to `DroppedInput` and an Image I/O/Core Graphics converter. Image I/O selects the primary still and explicitly decodes to SDR. A fresh 8-bit sRGB bitmap applies EXIF orientation at original dimensions and composites onto white. Fresh in-memory destinations encode JPEG at 0.90 and lossless LZW TIFF without passing source metadata, thumbnails, or auxiliary images. `@concurrent` keeps synchronous image processing off the main actor; immutable domain values are explicitly nonisolated.

The first green run exited 0 (1.579 seconds). Additional acceptance coverage passes for all eight orientations, fully/partially transparent pixels, a nonzero primary-image index, repeatable bytes, no output files, unchanged source, representations decoded after deleting the source, and unreadable/corrupt input. The final focused suite after TIFF compression exited 0. Each Xcode test invocation also compiles/typechecks the app and tests; no Swift warnings remained in the final focused run.

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Dropshot12 \
  -only-testing:DropshotTests/ImageConversionTests
```

Fixture provenance, independent analytical pixel expectations, tolerances, and integrity hashes are in `DropshotTests/Fixtures/README.md` and `SHA256SUMS`. The test uses signed sandboxed app-host execution.

## Focused performance evidence

Measured 2026-09-04 on macOS 26.6.2 (25G83), Apple M1 Max, 32 GB RAM. Compile the actual converter and its contracts with optimization, then use the checked-in 4000 × 3000 HEIC:

```sh
swiftc -O -parse-as-library -module-cache-path /tmp/DropshotModuleCache \
  Dropshot/Domain/DropModels.swift Dropshot/Workflow/DropWorkflow.swift \
  Dropshot/Workflow/DropCoordinator.swift Dropshot/Conversion/ImageConversion.swift \
  scripts/measure-image-conversion.swift -o /tmp/measure-image-conversion
/usr/bin/time -l /tmp/measure-image-conversion DropshotTests/Fixtures/12-megapixel.heic
```

After one 0.622-second warm-up, five conversions took 0.511, 0.514, 0.505, 0.476, and 0.496 seconds. Whole-process maximum resident size was 168,116,224 bytes; peak memory footprint was 160,711,424 bytes. Output sizes were JPEG 263,837 bytes and TIFF 248,280 bytes. An initial uncompressed TIFF path reached about 387 MB resident size; lossless LZW TIFF reduced retained representation and encoding-buffer costs while preserving pixels.

This is an optimized converter-only measurement on a low-entropy synthetic fixture, not the full Release Artifact benchmark. It does not establish photographic/HDR performance, Drop Zone latency, Clipboard Handoff time, or rendered UI responsiveness. Independent photographic/wide-color/HDR/contradictory-profile fixtures, source depth/gain-map coverage and real receiver checks remain broader MVP release gates, not passing checks here. SDR decoding uses Apple's documented [Image I/O decode request](https://developer.apple.com/documentation/imageio/kcgimagesourcedecodetosdr).

## Review

Two independent code-review agents inspected the staged implementation against baseline `91f90df34c621a31442a2becb6f37fb9a52c15d8`, using `git diff --cached <baseline>` because the requested commit follows review. Standards: no documented violations or actionable code smells. Spec: no blocking correctness findings. Both found one empty fixture-generation scratch file; it was removed before commit.

## Complete suite

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Dropshot12
```

Result: exit 0, 20.733 seconds. All image-conversion cases, the coordinator tracer, UI example, launch-performance test and launch test passed. Xcode emitted debugger-version diagnostic messages while launching UI tests, but no test failures or Swift compiler warnings.
