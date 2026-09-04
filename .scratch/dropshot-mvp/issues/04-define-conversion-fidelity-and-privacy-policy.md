Type: grilling
Status: resolved
Assignee: Codex
Blocked by:

## Question

What exact fidelity and privacy rules should govern JPEG quality, color profiles, orientation, dimensions, animation or auxiliary HEIC data, and metadata retention or removal during Default Conversion and Format Override?

## Answer

Apply a privacy-first **Conversion Policy**: preserve the source's primary still image as intended to appear, while discarding everything unnecessary to reproduce that visible image. Leave the original unchanged, and publish nothing when conversion fails.

Normalize both output formats to deterministic 8-bit-per-channel SDR sRGB through the system image pipeline's standard tone mapping. Embed only a newly generated sRGB ICC profile. When a source profile is absent, use the system decoder's standard HEIC interpretation; if malformed or contradictory color data prevents a deterministic raster, fail instead of guessing.

Apply source orientation to the pixels and emit upright output without an orientation dependency. Preserve the resulting full-resolution pixel dimensions; never resize, crop, heuristically rotate, or upscale. Convert only the designated primary still image. Discard animation frames, thumbnails, depth and disparity maps, gain maps, and all other auxiliary images or HEIC container data.

Default Conversion emits opaque RGB JPEG at a fixed quality of 0.90. If the primary image has transparency, composite it onto white. Format Override emits RGB or RGBA PNG and preserves transparency. The MVP exposes no quality control. A JPEG-mode transparency warning is deferred because alpha cannot be detected consistently before release for every Eligible Drag, particularly file promises.

Strip all source metadata, including EXIF, GPS, TIFF metadata, IPTC, XMP, timestamps, camera or device details, captions, keywords, ratings, copyright fields, filenames, orientation tags, embedded thumbnails, and editing history. Generate no software or creator tag. Apart from required JPEG/PNG structural data, the newly generated sRGB profile is the only metadata retained.

When a file promise requires materialization, keep its source only in Dropshot-controlled temporary storage for the current conversion. Delete it immediately after success or failure and remove abandoned Dropshot temporary inputs at next launch. Never persist converted output to disk.
