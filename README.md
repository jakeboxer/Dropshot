# Dropshot

Dropshot is a lightweight macOS menu-bar utility for turning a dragged HEIC image into clipboard-ready image content.

> [!NOTE]
> Dropshot is currently in early development. The menu-bar app shell is implemented; drag-and-drop conversion and clipboard handoff are planned but not yet available.

## Planned workflow

1. Drag a single HEIC image from any macOS application.
2. Drop it onto the temporary drop zone beneath the Dropshot menu-bar icon.
3. Paste the converted image into another application.

JPEG will be the default output format. Holding Option during the drag interaction will request PNG instead. The conversion is intended to publish the result directly to the clipboard without creating a user-visible permanent file.

## Requirements

- macOS 26.5 or later
- Xcode with support for the macOS 26.5 SDK

## Build and run

1. Clone the repository.
2. Open `Dropshot.xcodeproj` in Xcode.
3. Select the `Dropshot` scheme and a Mac run destination.
4. Press **Run** (`⌘R`).

The app has no Dock icon. Look for the downward-arrow icon in the menu bar after launch.

You can also build from the command line:

```sh
xcodebuild -project Dropshot.xcodeproj \
  -scheme Dropshot \
  -configuration Debug \
  build
```

## Tests

Run the unit and UI test targets in Xcode with `⌘U`, or from the command line:

```sh
xcodebuild test \
  -project Dropshot.xcodeproj \
  -scheme Dropshot \
  -destination 'platform=macOS'
```

The unit-test target covers descriptor-only Drag Observation classification, destination-only Accepted Drop creation, and the Accepted Drop through Default Conversion or PNG Format Override and Clipboard Handoff workflow, live modifier selection, and real HEIC conversion to owned JPEG/PNG bytes plus TIFF fallback. Pixel checks cover orientation, transparency, primary-image selection, and source preservation. The UI-test target currently contains launch smoke tests. The converter and live format state are available at the adapter seam; the menu-bar drag-and-drop UI is still planned.

## Project structure

```text
Dropshot/          Application source and assets
DropshotTests/     Unit tests
DropshotUITests/   UI tests
CONTEXT.md         Product terminology and domain language
```

## Contributing

Issues and pull requests are welcome. Please keep user-facing terminology consistent with [`CONTEXT.md`](CONTEXT.md).
