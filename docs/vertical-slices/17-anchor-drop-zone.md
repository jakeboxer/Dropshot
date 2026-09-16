# Vertical Slice 17: Anchor the Drop Zone across screen contexts

## Public seam and behavior

Issue #17 continues at the established `DropZonePanelController` presentation seam. On every visible presentation, the controller reads the live status-item button frame, places the 202 × 170 point Drop Zone eight points beneath its bottom edge, and horizontally centers the panel before clamping its complete frame to that anchor's screen `visibleFrame`.

The controller continues to own only presentation behavior. A narrow visible-frame resolver is injectable for deterministic display-arrangement examples; production selects the anchor window's screen first, then a screen containing the anchor frame, then the main screen. While the Drop Zone is requested, view-frame, view-bounds, anchor-window move/resize/screen, screen-parameter, and active-Space notifications recompute the frame from the live anchor. Re-anchoring removes the prior observations.

`DropZonePanel` remains borderless and nonactivating, cannot become key or main, and uses `canJoinAllSpaces`, `canJoinAllApplications`, and `fullScreenAuxiliary` collection behaviors. Apple's [`canJoinAllApplications` contract](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications) specifically covers joining other applications' full-screen Spaces and Stage Manager sets; the flags establish the intended platform policy, while the real-system checks below remain required visual evidence.

## Red → green evidence

Each production change was exercised through the existing presentation seam.

1. `DropZonePanelTests/dropZoneIsCenteredEightPointsBelowTheLiveAnchor` first failed to compile because the controller had no visible-screen geometry input. The controller then resolved the live anchor frame, computed the centered eight-point offset, and clamped the result. The centered example and four edge examples on a negative-origin display passed.
2. `DropZonePanelTests/visibleDropZoneFollowsTheLiveAnchor` failed because moving the anchor window left the already-presented panel at its original origin. Observing live anchor and screen geometry changes made the test pass. `visibleDropZoneReclampsWhenTheDisplayContextChanges` also covers screen-parameter and active-Space changes with different injected visible frames.
3. `DropZonePanelTests/dropZoneIsANonactivatingRegisteredPanelWithDefaultGuidance` failed its three new Space/full-screen collection-behavior assertions. Adding `canJoinAllSpaces`, `canJoinAllApplications`, and `fullScreenAuxiliary` while retaining the nonactivating panel behavior made them pass.
4. `DropZonePanelTests/dropZoneAnchorsToARealStatusItemOnTheCurrentScreen` creates a system `NSStatusItem`, waits up to one second for AppKit to place its button on a screen, presents through the production controller, and verifies that the complete panel is visible and is centered/eight points below except where the visible-frame edge requires clamping.

Focused invocation:

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/Dropshot17SubagentFocusedI-20260915 \
  -only-testing:DropshotTests/DropZonePanelTests CODE_SIGNING_ALLOWED=NO
```

Result: exit 0. All 9 `DropZonePanelTests` passed. No compiler warnings were reported.

## Complete suite and typechecking

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/Dropshot17RootFinal-20260915
```

Result: exit 0. The signed unit and UI suite passed all 46 tests (78 runs including parameterized cases), with zero failures or skips. The build typechecked the production and test code without compiler warnings. Xcode emitted non-failing debugger-version lookup diagnostics during UI launches; the result bundle reports no runtime warnings. `git diff --check` also passed.

## Real-system and display-arrangement evidence

Automated live check on 2026-09-15:

- Debug test host built from baseline `35356762ae775e309e70db4ffede516dc2538d44` plus this slice.
- macOS 26.6.2 (25G83), Apple M1 Max, Xcode 27.0 (27A266a).
- One built-in Color LCD, 3456 × 2234 Retina; no external display was attached.
- The production controller anchored a real system status-item button to its current screen. The panel remained wholly inside that screen's visible frame and satisfied the centered/eight-point relationship or its defined edge-clamp alternative.
- Deterministic examples passed for left, right, bottom, and top clamping on a 1920 × 1080 negative-origin display, and for reclamping across changed positive- and negative-origin display contexts.

### Two-display follow-up, 2026-09-15

The built-in Color LCD and a Dell U4025QW are now connected in extended mode (mirroring off). System Information reports 7680 × 3240 pixels for the Dell, with a 3840 × 1620 point UI at 60 Hz; the built-in display remains the main display.

The signed focused panel suite was rerun with both displays connected:

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/Dropshot17TwoDisplays-20260915 \
  -only-testing:DropshotTests/DropZonePanelTests
```

Result: exit 0; all 9 panel tests passed, including the real status-item anchoring check. This is evidence for the current live anchor with two displays attached, not evidence that a physical drag was exercised on each display. The desktop-control tool supports complete drag-and-release operations but cannot pause with the mouse button held for an intermediate observation; a user-held drag was requested to complete that observation.

#### Observed physical drag on Dell

The user held an HEIC drag on the Dell while the Debug app from commit `70acc1d` was running (`/tmp/Dropshot17RootFinal-20260915/Build/Products/Debug/Dropshot.app`). The desktop tool observed “Drop HEIC here,” “Release to copy as JPEG,” and “Hold ⌥ for PNG”; its panel screenshot showed all content without clipping.

Read-only AppKit/Core Graphics measurements during the held drag:

| Measurement | Result (points) |
| --- | --- |
| Built-in screen frame | `(0, 0, 1728, 1117)` |
| Built-in visible frame | `(0, 0, 1728, 1084)` |
| Dell frame and visible frame | `(1728, 448, 3840, 1620)` |
| Panel frame, converted to AppKit coordinates | `(4853, 1861, 202, 170)` |
| Panel alpha / on-screen state | `1` / on screen |
| Pressed mouse buttons | `1` (left held) |

The panel is wholly inside the Dell's actual visible frame. Core Graphics reported `(4853, -914, 202, 170)` in top-origin coordinates; conversion uses the primary display's top edge at `1117`. Both displays have a backing scale of `2`. This validates physical placement and visible presentation on the Dell in the current right-and-above arrangement. It does not exercise an edge clamp or independently measure the status-button gap.

The foreground application at observation time was Codex, not Dropshot. This confirms Dropshot was not foreground at that instant, but the user's reply prevents treating it as proof that Finder retained focus throughout the drag. The exact source fixture was not independently recorded.

#### Observed physical drag on built-in display

The first built-in attempt was confounded by Command-Tab: the user reported that the panel initially appeared on the built-in display, then moved to the Dell when they switched to Codex on the Dell to reply. The subsequent measurement showed the held pointer on the built-in display and the panel on the Dell. That observation does not establish incorrect initial placement; the initial claim that it proved a placement bug is withdrawn. No production code was changed on that basis.

After the user moved Codex to the built-in display and repeated the held drag, the desktop tool again observed complete JPEG guidance without clipping. Measurements from the same running build were:

| Measurement | Result (points) |
| --- | --- |
| Held pointer, AppKit coordinates | `(1102.30078125, 582.6171875)` |
| Built-in visible frame | `(0, 0, 1728, 1084)` |
| Panel frame, Core Graphics coordinates | `(1015, 39, 202, 170)` |
| Panel frame, converted to AppKit coordinates | `(1015, 908, 202, 170)` |
| Panel alpha / on-screen state | `1` / on screen |
| Pressed mouse buttons | `1` (left held) |
| Foreground application | Codex |

The pointer and complete panel were on the built-in display, with the panel wholly within its actual visible frame. Together with the Dell observation, this passes visible physical placement on each display in the current right-and-above arrangement. Neither observation forces an edge clamp, independently measures the live status-button gap, or proves uninterrupted source-app focus. The observations use a Debug build rather than a Release Artifact.

#### User-confirmed manual checks

After the measured two-display checks, the user reported: “manually confirmed all 3 work.” This confirms the three follow-up checks provided in the conversation:

| Check | Expected behavior | Result |
| --- | --- | --- |
| Right screen edge | Move the status item toward the right edge and drag an HEIC; the complete panel remains on-screen even when centering must yield to clamping. Repeat on both displays. | Pass, user-confirmed |
| Another desktop Space | Start an HEIC drag in another Space; the panel appears there without switching desktops. | Pass, user-confirmed |
| Full-screen Finder | Drag an HEIC from full-screen Finder; the panel appears above Finder and the drag remains uninterrupted. | Pass, user-confirmed |

These results are manual user testimony, not additional agent measurements or captured screenshots. Together with the automated suite and measured placement on both physical displays, they complete the agreed implementation acceptance checks for issue #17. No production changes were needed after validation.

Release Artifact validation remains a separate release gate. The current record does not claim testing of additional physical display layouts, left-edge positions, Stage Manager sets, or a separate before/after foreground-app trace. Repeat and capture the applicable release matrix below against the actual Release Artifact; these broader release checks do not reopen the three confirmed implementation checks.

Repeat the live status-item test for every build. For release evidence, also record the Release Artifact, display layout and scale, source application, active Space/full-screen state, status-item edge position, expected centered/clamped frame, observed frame, source-app focus before and after presentation, and a screenshot or 60-fps recording for each representative physical arrangement.

### Repeatable manual procedure

1. Launch the build under test and open `DropshotTests/Fixtures` in Finder. Use a single HEIC fixture and record its name and the build identity.
2. Start dragging the fixture and hold it while the Drop Zone appears. Check that the source application retains focus, the panel is centered eight points below the live Dropshot button when space permits, and the complete panel stays inside the visible area. Release outside the panel to end the check.
3. Repeat with the status item near each horizontal screen edge, recording any clamp and the Dock/menu-bar configuration. Restore the original status-item position afterward.
4. Repeat with an external display to the left, right, and vertically offset from the built-in display, activating each display in turn. Record resolution, scale, display origins, and whether displays have separate Spaces.
5. Repeat on another desktop Space and with another application full screen. Confirm the panel appears in that context without activating Dropshot or switching away. If Stage Manager is enabled, repeat within another application's set.
6. Attach the observations and visual evidence for each case. Mark unavailable arrangements as blocked; do not substitute synthetic-frame test results for physical observations.

## Review

Independent Standards review reported no findings. Independent Spec review initially reported one acceptance finding: real-system validation was partial. Subsequent measured placement on both physical displays and the user's confirmation of edge, Space, and full-screen checks resolve that implementation acceptance finding. The implementation is ready; the broader Release Artifact validation remains part of release preparation.
