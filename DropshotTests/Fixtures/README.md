# HEIC fixture provenance

These synthetic charts are owned by this project and generated with Apple's Image I/O HEIC encoder on macOS 26.6.2 (25G83), Apple M1 Max. They contain no user photographs. Regenerate intentionally using `swift scripts/generate-heic-fixtures.swift DropshotTests/Fixtures`; encoded bytes can change across OS encoder versions. `SHA256SUMS` protects the checked-in inputs, not pixel correctness.

The independent pixel oracle is the chart layout, specified before conversion: a 96 × 64 raster with red/green above blue/yellow, each quadrant a solid sRGB primary. For orientations 1–8, the expected displayed quadrant order is written explicitly in `ImageConversionTests`; dimensions swap for 5–8. Samples at quadrant centers allow 12 code values of absolute error per RGB channel for HEIC/JPEG loss and chroma subsampling, away from boundaries. This is a synthetic analytical oracle; independently approved photographic reference rasters remain part of the broader MVP release gate.

- `oriented-metadata.heic`: orientation 6, with deliberately identifiable EXIF comment, GPS latitude and TIFF artist.
- `orientation-1.heic` through `orientation-8.heic`: identical source chart, every EXIF orientation.
- `transparency.heic`: fully transparent top-left and 50% red top-right; expected white and (255,127,127) after white compositing. Blue/yellow remain opaque.
- `primary-second.heic`: two still images, with the second 96 × 64 transparent chart marked primary; the first is a 4000 × 3000 decoy. The test asserts the fixture's nonzero primary index.
- `12-megapixel.heic`: fixed 4000 × 3000 synthetic chart for focused conversion timing/memory. Its low entropy is not representative of photographic compression costs; the full release benchmark still requires the agreed photographic fixture.

Wide-color/HDR, malformed or contradictory color profiles, depth/gain-map source corpora and independent photographic references are not supplied by these fixtures. Missing files and arbitrary corrupt bytes are covered by runtime failure tests. No missing release check is represented as passing.
