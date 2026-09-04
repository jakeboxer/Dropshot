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

**Current Error**:
The most recent failed conversion in the running app session, cleared by the next successful conversion or by restarting Dropshot.
_Avoid_: error history, conversion history
