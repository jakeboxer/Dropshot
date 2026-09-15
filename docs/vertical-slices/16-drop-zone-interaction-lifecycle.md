# Vertical Slice #16: Drop Zone interaction lifecycle

## Public seams and behavior

Issue #1 pre-agrees `DropWorkflow` as the highest deterministic interaction seam. Issue #16 supplies this slice's acceptance criteria. `DropWorkflow` now owns whether a physical drag is idle, active, or suppressed after abandonment until mouse release. Destination entry and update synchronously select JPEG or PNG guidance; destination exit, mouse-up, interruption, and cancellation dismiss without conversion or Clipboard Handoff effects. Suppression prevents later observations from the same abandoned drag from presenting the Drop Zone again.

`DropZonePresentation` separates active guidance from terminal success. The presenter maps JPEG guidance to “Drop HEIC here,” “Release to copy as JPEG,” and “Hold ⌥ for PNG”; PNG guidance changes the latter lines to “Release to copy as PNG” and “Release ⌥ for JPEG.” Successful Clipboard Handoff completion replaces the orb border with a checkmark and shows “Copied,” “Ready to paste,” and the selected format. The workflow emits an 800 ms dismissal effect tagged with the Drop ID, so an obsolete timer cannot dismiss newer presentation. A new physical drag replaces success immediately.

`AppKitDragObserver` remains a stateless platform adapter. Global and local AppKit monitors report mouse drag and mouse-up events, while a main-run-loop poll publishes the current button and Option state without keyboard monitoring or permission-gated APIs. That physical-button poll is the fallback when AppKit does not deliver a mouse-up callback: once the left button is no longer pressed, the workflow ends the interaction. A stationary drag remains valid indefinitely while the button is held; elapsed time alone is not evidence of abandonment. `DropZoneView` forwards destination entry, update, exit, drop, and cancellation callbacks. `DropCoordinator` returns those inputs to the workflow, renders changed presentation synchronously, and runs only the success-feedback timer.

The live application still uses the presentation-only coordinator established by issue #15. `DropCoordinator.accept(_:)` covers Accepted Drop conversion, Clipboard Handoff completion, and success feedback through injected adapters; issue #20 owns the production atomic clipboard adapter and will make that path live without changing this interaction contract.

## Red → green evidence

Each behavior began with a failing test at a pre-agreed seam before its minimum production behavior.

1. `DropWorkflowTests/destinationLifecycleUpdatesGuidanceAndAbandonmentDismissesSilently` failed to compile because destination entry, update, exit, mouse-up, interruption, cancellation, and `DropZonePresentation` did not exist. Adding the workflow events and presentation state made the focused workflow suite pass.
2. `DropWorkflowTests/successfulHandoffShowsTimedFeedbackThatANewDragReplaces` failed for the missing format-bearing Clipboard Handoff completion, 800 ms dismissal effect, and elapsed-feedback event. Adding generation-tagged success presentation made the focused workflow suite pass.
3. `DropZonePanelTests/guidanceAndSuccessPresentationUseTheApprovedCopy` failed for the missing `render` seam and content model. Adding synchronous content rendering for JPEG, PNG, and success made the panel suite pass.
4. `DragPasteboardSnapshotTests/dragObserverPublishesLivePointerState` failed for the missing pointer-state boundary. Adding button and Option polling plus mouse-up monitoring made the adapter suite pass.
5. The initial implementation included an inactivity timeout. After product review rejected elapsed time as an abandonment signal, `DropCoordinatorTests/stationaryEligibleDragRemainsPresentedWhileMouseButtonIsHeld` failed under the old one-second timer. Removing the timer and timeout event made the test pass while retaining explicit and physical-button-driven cleanup.

Focused invocation:

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Dropshot16ReviewFixes \
  -only-testing:DropshotTests/DropWorkflowTests \
  -only-testing:DropshotTests/DropCoordinatorTests \
  -only-testing:DropshotTests/DropZonePanelTests \
  -only-testing:DropshotTests/DragPasteboardSnapshotTests CODE_SIGNING_ALLOWED=NO
```

Result: exit 0. All 19 focused workflow, coordinator, panel, and AppKit adapter test cases passed without compiler warnings.

## Complete suite and typechecking

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Dropshot16FinalFullTests
```

Result: exit 0. All unit tests and the UI smoke, launch, and launch-performance tests passed. No Swift compiler warnings were reported; Xcode emitted only non-failing debugger-version lookup diagnostics during UI-test launches.

## Capability and validation boundaries

Static inspection found no Core Graphics event tap, Accessibility trust API, Apple Events usage declaration, or Input Monitoring integration. Lifecycle observation uses only AppKit global/local mouse monitors, destination callbacks, `NSEvent.pressedMouseButtons`, and modifier-state polling.

Validated on 2026-09-15 with macOS 26.6.2 (25G83), Apple silicon, and Xcode 27.0 (27A266a). Cross-application Escape/interruption checks and 60-fps visual timing evidence remain mandatory release-candidate checks under the Validation Contract; this slice establishes their deterministic workflow behavior and production event routing.

## Review

The independent Standards review found that early adapter-local flags inferred interaction state and that terminal feedback had been conflated with an active Drop Zone request. The independent Spec review found that exit could re-present from the same physical drag. The final design moved suppression into `DropWorkflow`, made the AppKit observer stateless, and limited `isDropZoneRequested` to active guidance. Re-review tightened suppression against queued destination callbacks, made orb styling explicit instead of deriving it from an SF Symbol string, and removed duplicated guidance-update logic. Product review then removed the inactivity timeout entirely: the physical-button poll supplies missed-mouse-up cleanup without incorrectly dismissing a stationary drag. The Spec review also identified the missing Vertical Slice record; this document resolves it. Production atomic Clipboard Handoff remains intentionally owned by issue #20.
