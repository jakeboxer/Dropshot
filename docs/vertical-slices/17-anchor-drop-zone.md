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

The following mandatory Validation Contract evidence remains blocked or outstanding and is not counted as a pass:

- Physical multi-display anchoring and edge checks are blocked because only one display is attached.
- Actual visibility and anchoring after switching Spaces, inside another application's full-screen Space, and across Stage Manager sets have not been visually exercised. Automated tests verify the AppKit collection policy and reposition notifications only.
- A real cross-application drag remains necessary to verify that presentation does not change source-application focus; automated coverage verifies the nonactivating style and that the panel cannot become key or main.

Repeat the live status-item test for every build. For release evidence, also record the Release Artifact, display layout and scale, source application, active Space/full-screen state, status-item edge position, expected centered/clamped frame, observed frame, source-app focus before and after presentation, and a screenshot or 60-fps recording for each representative physical arrangement.

### Repeatable manual procedure

1. Launch the build under test and open `DropshotTests/Fixtures` in Finder. Use a single HEIC fixture and record its name and the build identity.
2. Start dragging the fixture and hold it while the Drop Zone appears. Check that the source application retains focus, the panel is centered eight points below the live Dropshot button when space permits, and the complete panel stays inside the visible area. Release outside the panel to end the check.
3. Repeat with the status item near each horizontal screen edge, recording any clamp and the Dock/menu-bar configuration. Restore the original status-item position afterward.
4. Repeat with an external display to the left, right, and vertically offset from the built-in display, activating each display in turn. Record resolution, scale, display origins, and whether displays have separate Spaces.
5. Repeat on another desktop Space and with another application full screen. Confirm the panel appears in that context without activating Dropshot or switching away. If Stage Manager is enabled, repeat within another application's set.
6. Attach the observations and visual evidence for each case. Mark unavailable arrangements as blocked; do not substitute synthetic-frame test results for physical observations.

## Review

Independent Standards review reported no findings. Independent Spec review reported one acceptance finding: real-system validation is partial. The implementation aligns with the positioning, clamping, and collection-policy requirements, but issue #17 cannot be counted fully accepted until the outstanding real-system checks above pass.
