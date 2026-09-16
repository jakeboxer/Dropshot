# HEIC fixture provenance

These synthetic charts are owned by this project and generated with Apple's Image I/O HEIC encoder on macOS 26.6.2 (25G83), Apple M1 Max. They contain no user photographs. Regenerate intentionally using `swift scripts/generate-heic-fixtures.swift DropshotTests/Fixtures`; encoded bytes can change across OS encoder versions. `SHA256SUMS` protects the checked-in inputs, not pixel correctness.

The independent pixel oracle is the chart layout, specified before conversion: a 96 × 64 raster with red/green above blue/yellow, each quadrant a solid sRGB primary. For orientations 1–8, the expected displayed quadrant order is written explicitly in `ImageConversionTests`; dimensions swap for 5–8. Samples at quadrant centers allow 12 code values of absolute error per RGB channel for HEIC/JPEG loss and chroma subsampling, away from boundaries. This is a synthetic analytical oracle; independently approved photographic reference rasters remain part of the broader MVP release gate.

- `oriented-metadata.heic`: orientation 6, with deliberately identifiable EXIF comment, GPS latitude and TIFF artist.
- `orientation-1.heic` through `orientation-8.heic`: identical source chart, every EXIF orientation.
- `transparency.heic`: fully transparent top-left and 50% red top-right; expected white and (255,127,127) after white compositing. Blue/yellow remain opaque.
- `primary-second.heic`: two still images, with the second 96 × 64 transparent chart marked primary; the first is a 4000 × 3000 decoy. The test asserts the fixture's nonzero primary index.
- `12-megapixel.heic`: fixed 4000 × 3000 synthetic chart for focused conversion timing/memory. Its low entropy is not representative of photographic compression costs; the full release benchmark still requires the agreed photographic fixture.

## Conversion Policy corpus (#19)

Regenerate the additional 32 × 24 inputs with `swift scripts/generate-conversion-policy-fixtures.swift DropshotTests/Fixtures`. The script records generation environment and verifies source properties, including the presence of real auxiliary data. It does not run Dropshot to create expected pixels.

- `display-p3.heic`: an embedded Display P3 ICC profile and four flat patches. Displayed top-left, top-right, bottom-left, bottom-right P3 components are (0.50, 0.40, 0.30), (0.30, 0.55, 0.40), (0.30, 0.40, 0.60), and (0.50, 0.50, 0.50).
- `absent-color.heic`: the same chart encoded as sRGB, with the container color property replaced by an optional free-space property. The decoder's standard HEIC interpretation is expected: (128,102,77), (77,140,102), (77,102,153), and (128,128,128).
- `malformed-color.heic`: the sRGB chart with its `nclx` color-primaries value replaced by the invalid code 65535. ImageIO silently resolves this to sRGB; Dropshot must reject the explicit invalid declaration.
- `malformed-icc.heic`: the P3 input with only the mandatory ICC `acsp` signature changed to `bad!`. ImageIO also silently falls back to sRGB for this input. Expected result is failure without either output representation.
- `contradictory-color.heic`: two valid but conflicting `nclx` properties associated with the primary image (sRGB and BT.2020/PQ). ImageIO selects one; Dropshot rejects this ambiguity.
- `malformed-size.heic`: an oversized color-property box length; `malformed-icc-size.heic`: an ICC declared profile size beyond the available payload. Both must fail without representations.
- `disparity-auxiliary.heic`: the sRGB chart plus an actual 8 × 6 Float32 disparity plane. Tests establish that the input contains that plane, then check that output contains only primary pixels and no auxiliary data. Thumbnail API results are not a reliable absence check: ImageIO can return the primary raster even without an embedded thumbnail.

## Independent reference rasters

`python3 scripts/generate-conversion-reference-rasters.py DropshotTests/Fixtures` writes small PNG references using only Python's standard library. It does not decode HEIC, call Apple image APIs, or invoke the production converter. Orientation references use explicitly enumerated displayed quadrants. The transparency reference contains clear, half-red, blue, and yellow quadrants.

The P3 reference converts the source patch values with the [W3C CSS Color 4 matrices and transfer functions](https://www.w3.org/TR/css-color-4/#color-conversion-code): Display P3 → XYZ D65 → linear sRGB → encoded sRGB. The expected 8-bit values are (132,101,73), (49,142,99), (69,103,157), and (128,128,128). A separate investigation cross-checked these values using Core Graphics color conversion; the checked-in raster is generated from the equations. The top-right red component differs by 28 levels from relabeling P3 bytes, so the tolerance detects that error.

Tests compare all interior pixels with maximum absolute error ≤12 per premultiplied RGBA channel (≤4 for the P3 PNG/TIFF outputs), excluding four pixels at each quadrant's edges to avoid HEIC/JPEG chroma-boundary artifacts. They also check dimensions, 8-bit depth, sRGB output, and corner expectations independently. Hashes cover source files and reference PNGs solely to detect accidental changes.

**Independent review:** on 2026-09-15, a separate fixture-review sub-agent approved these analytical references after checking the W3C matrices, inspecting all ten PNGs and their quadrant pixels, and confirming byte-identical regeneration. The reviewer did not author the reference generator. This is automated independent review, not human signoff or approval of photographic/HDR reference rasters. HDR tone-mapping, source gain-map/depth/animation variants, and photographic release performance still require the broader Validation Contract evidence. No missing or blocked release check is represented as passing.
