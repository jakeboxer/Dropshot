# Dropshot

Dropshot is a macOS menu-bar utility that turns a dragged HEIC image into clipboard-ready image content through a transient drop target.

## Language

**Eligible Drag**:
A drag session containing exactly one HEIC file and no other items, originating from any macOS application.
_Avoid_: Messages drag, supported drag

**Drop Zone**:
The transient target shown beneath the menu-bar item while an Eligible Drag is active.
_Avoid_: window, shelf, tray

**Default Conversion**:
Conversion of an Eligible Drag to JPEG when no format override is requested.
_Avoid_: normal conversion

**Format Override**:
A user request, made by holding the Option key during the drag interaction, to convert the image to PNG instead of JPEG.
_Avoid_: hotkey conversion, alternate conversion

**Clipboard Handoff**:
Publishing converted image content in clipboard representations that compatible macOS applications can paste, without creating a user-visible permanent file.
_Avoid_: export, saved output

**Visible Image**:
The source HEIC's primary still image as it is intended to appear after applying its orientation and color interpretation, at its original pixel dimensions. It excludes metadata, animation, depth or disparity maps, thumbnails, gain maps, and other auxiliary image data.
_Avoid_: original file, all source data

**Conversion Policy**:
Preserve the Visible Image while discarding source information that is unnecessary to reproduce its appearance. Produce deterministic 8-bit-per-channel SDR sRGB output, using the system image pipeline's standard tone mapping and embedding only a newly generated sRGB profile. When source color information is absent, use the system decoder's standard HEIC interpretation; fail rather than guess when malformed or contradictory color data prevents a deterministic raster. Apply orientation to the pixels; preserve full-resolution pixel dimensions without resizing, cropping, or upscaling; and convert only the primary still image. Strip all source metadata and auxiliary images. Default Conversion uses a fixed JPEG quality of 0.90 and composites transparency onto white. Format Override preserves transparency. Neither mode exposes a quality preference in the MVP.
_Avoid_: lossless conversion, metadata-preserving conversion

**Ephemeral Input**:
A source file materialized in Dropshot-controlled temporary storage solely to fulfill a file promise and perform the current conversion. Delete it immediately after success or failure, and remove abandoned Dropshot temporary inputs at the next launch.
_Avoid_: cached source, conversion history

**Current Error**:
The most recent failed conversion in the running app session, cleared by the next successful conversion or by restarting Dropshot.
_Avoid_: error history, conversion history
