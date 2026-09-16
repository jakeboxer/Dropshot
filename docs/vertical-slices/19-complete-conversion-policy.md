# Vertical Slice #19: enforce the Conversion Policy

## Public seam and ownership

Issue #1 pre-agrees `ImageConversion.convert(_:)` as the pixel-correctness seam; issue #19 supplies this slice's acceptance criteria. The converter owns an immutable input byte snapshot, validates the color declarations of the primary Visible Image, and passes the same bytes to ImageIO. Source access lifetime and Clipboard Handoff remain outside the converter.

`HEICColorInformation` reads only the ISO-BMFF structures needed to associate primary and derived source items with color properties. Bounds-checked box sizes, supported versions, unique structural boxes, valid property associations, registered CICP values, and ICC header/length/color-space validation prevent silently repairing malformed declarations. Conflicting declarations of the same color family on one item fail. Legal ICC plus nclx coexistence is retained; unrelated auxiliary image color declarations do not control the Visible Image. Absence of a color property continues to use the system HEIC interpretation.

The existing raster path still explicitly requests system SDR decoding, applies orientation at full resolution, renders 8-bit sRGB, composites JPEG onto white at quality 0.90, preserves PNG alpha, and encodes fresh requested-format/TIFF representations without copying source metadata or auxiliary data.

## Red → green evidence

The original converter returned successful JPEG/PNG and TIFF buffers for both invalid nclx primaries (65535) and a corrupted ICC `acsp` signature. ImageIO reported complete input status and synthesized an sRGB color space in both cases. The public test `malformedColorFailsWithoutRepresentations` failed for both output formats before the validation change. Source status or decoded color-space checks alone could not distinguish malformed declarations from absent color information.

Additional coverage exercises oversized color boxes, oversized ICC declarations, two conflicting valid nclx properties, Display P3 normalization, absent-color defaults, a real disparity plane, full 4000 × 3000 dimensions and pixels, all orientations, alpha preservation, and metadata exclusion. The ten reference PNGs are generated with independent mathematical expectations and reviewed by a separate sub-agent; they are not converter-generated golden files. Source/reference hashes are integrity checks only. See `DropshotTests/Fixtures/README.md` for provenance, review evidence, exact tolerances, and limits.

A test initially assumed ImageIO's thumbnail API returning a raster proved an embedded thumbnail. Experiments showed it can return the primary raster for fresh output. That invalid assertion was removed; single-image counts and auxiliary-data checks remain, while production explicitly disables thumbnail embedding and never copies source properties.

## Verification

Focused test command (also compiles/typechecks the application and tests):

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Dropshot19 \
  -only-testing:DropshotTests/ImageConversionTests
```

Focused result: 11 test functions, 41 cases including parameterized runs, all passed. Full unit/UI suite uses the same command without `-only-testing`: 64 test functions, 109 cases, all passed; no skips. The full run took 33.8 seconds. Xcode recorded ImageIO internal priority-inversion diagnostics during fixture conversion and debugger-version messages for UI launch; no test failures or Swift compiler warnings occurred in the project run.

The sandbox prevented Xcode contacting its test manager, so signed-host test runs used the normal macOS execution environment. The first P3-only selector matched no test cases and is not counted as evidence; subsequent runs selected the complete test class.

## Focused performance

Measured on macOS 26.6.2 (25G83), Apple M1 Max, with an optimized converter executable and the existing synthetic 12-megapixel fixture. One warm-up took 0.800 seconds; five JPEG conversions took 0.688, 0.685, 0.685, 0.682, and 0.681 seconds. Whole-process maximum resident size was 170,246,144 bytes and peak memory footprint was 161,514,240 bytes. Both stay below the 300 MB additional-memory budget even when conservatively counting the whole process.

```sh
swiftc -O -parse-as-library -module-cache-path /tmp/Dropshot19ModuleCache \
  Dropshot/Domain/*.swift Dropshot/Workflow/*.swift \
  Dropshot/PlatformAdapters/*.swift Dropshot/Conversion/*.swift \
  scripts/measure-image-conversion.swift -o /tmp/Dropshot19-measure
/usr/bin/time -l /tmp/Dropshot19-measure DropshotTests/Fixtures/12-megapixel.heic
```

Final PNG measurement: one 0.915-second warm-up, then 0.750, 0.737, 0.776, 0.788, and 0.775 seconds. Peak resident size was 410,435,584 bytes while physical memory footprint was 161,858,496 bytes. A matched run of the original converter measured 409,944,064 bytes resident and 161,432,536 bytes footprint, so the high PNG resident figure predates this change (difference under 0.5 MB). These conflicting process-level metrics do not establish the release contract’s additional-memory result; retain both and resolve it with the specified release profiling procedure.

This is a focused synthetic converter measurement, not the photographic Release Artifact or full Clipboard Handoff benchmark. The standalone compiler invocation emits an existing sendability warning in `DragPasteboardSnapshot.swift`; the project build applies its own actor-isolation settings. A sandboxed earlier benchmark was discarded because the codec used a different fallback path and the OS denied memory statistics.

## Validation limits

This corpus covers wide color with Display P3 and auxiliary data with real disparity, satisfying those fixture categories in #19. It does not establish photographic HDR tone-mapping accuracy, real gain-map/depth/animation receiver behavior, the entire receiver matrix, or release readiness. Those remain broader MVP Validation Contract checks. The reference approval is independent automated review of synthetic charts, not human or photographic signoff.

## Review

Two independent sub-agents reviewed the staged diff against initial HEAD `25de135ceda250ee49aff403c5f3f37dbc1d62b3` using `git diff --cached <baseline>` so review preceded the requested commit. The standards review found no documented-standard violations and one duplicated test-rasterization helper; the helper was consolidated and the focused suite rerun. The focused rerun passed all 41 cases. The spec review found no missing or incorrect requirements and no scope creep. Final review outcome: Standards 0 unresolved findings (1 duplication fixed); Spec 0 findings.
