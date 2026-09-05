# Vertical Slice #15: Nonactivating Drop Zone

## Public seams and behavior

Issue #1 pre-agrees `DragClassifier` and `DropWorkflow` as the classification and interaction seams. Issue #15 supplies this slice's acceptance criteria.

`AppKitDragObserver` uses global and local AppKit `leftMouseDragged` monitors to sample the named drag pasteboard. It requests no Accessibility, Input Monitoring, automation, or event-tap capability. `DragPasteboardSnapshot` converts each pasteboard item into the immutable descriptor vocabulary from issue #14, preserving the complete item count. The coordinator forwards that Drag Observation to `DropWorkflow`; only the resulting `isDropZoneRequested` state drives presentation.

`DropZonePanelController` owns a 202 × 170 point, borderless `NSPanel` with the nonactivating style. Its registered content view accepts file-URL and `NSFilePromiseReceiver` drag types and renders the default Format Orb copy: “Drop HEIC here,” “Release to copy as JPEG,” and the passive “Hold ⌥ for PNG” footer. It initially positions the panel eight points beneath the live status-item button; screen clamping and multi-display/Space validation remain issue #17.

The registered destination takes a fresh pasteboard snapshot in `performDragOperation`. It creates an `AcceptedDrop` only through `DragClassifier.acceptDrop(atDestination:input:optionHeld:)`; invalid destination evidence returns `false`, dismisses the Drop Zone, and never reaches the accepted-drop callback. File promises are registered and classified, but fulfillment remains issue #18 and therefore cannot yet complete a drop.

The application delegate composes the observer, workflow coordinator, and Drop Zone. Destination acceptance and rejection both end this slice's presentation interaction through `DropWorkflow`; the accepted-drop callback remains the seam for later production processing composition, and atomic ClipboardPublication is intentionally deferred to issue #20. Invalid drops never reach that callback, so they cannot start conversion or a Clipboard Handoff.

## Red → green evidence

Each numbered behavior was added before its minimum production behavior.

1. `DropCoordinatorTests/eligibleDragObservationPresentsAndIneligibleObservationDismissesTheDropZone`: compilation failed for the missing `DropZonePresenting` seam; adding the presentation adapter boundary and coordinator rendering passed.
2. `DropZonePanelTests/dropZoneIsANonactivatingRegisteredPanelWithDefaultGuidance`: compilation failed for the missing panel and guidance types; adding the nonactivating registered panel and Format Orb content passed.
3. `DropZonePanelTests/dropZoneRejectsIneligibleDestinationPayloadBeforeAcceptance`: compilation failed for the missing destination method; adding destination-only `AcceptedDrop` creation passed.
4. `DragPasteboardSnapshotTests/dragObserverPublishesAPasteboardSnapshotWithoutRequestingPermissions`: compilation failed for the missing observer; adding AppKit mouse-drag monitors and snapshot delivery passed.

The pasteboard snapshot tests additionally verify one explicit HEIC file URL becomes an Eligible Drag observation and that multiple items remain multiple items and are authoritatively rejected.

Focused invocation:

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Dropshot15Tests \
  -only-testing:DropshotTests/DragClassifierTests \
  -only-testing:DropshotTests/DropWorkflowTests \
  -only-testing:DropshotTests/DropCoordinatorTests \
  -only-testing:DropshotTests/DropZonePanelTests \
  -only-testing:DropshotTests/DragPasteboardSnapshotTests CODE_SIGNING_ALLOWED=NO
```

Result: exit 0. All focused classifier, workflow, coordinator, pasteboard snapshot, and panel tests passed. No Swift compiler warnings were reported.

## Complete suite and typechecking

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Dropshot15FullTests
```

Result: exit 0. All unit tests and the UI smoke, launch, and launch-performance tests passed. The complete run finished without Swift compiler warnings; Xcode emitted non-failing debugger-version-store diagnostics while launching UI-test iterations.

## Capability and validation boundaries

Static inspection found no Core Graphics event tap, Accessibility trust API, Apple Events usage declaration, or Input Monitoring integration in the application or project. Observation is implemented only with `NSEvent.addGlobalMonitorForEvents` and `NSEvent.addLocalMonitorForEvents` for mouse-dragged events.

Validated on 2026-09-05 with macOS 26.6.2 (25G83), Apple silicon, and Xcode 26.6 (17F113). Cross-application real drag checks, exact screen-edge placement, lifecycle cancellation, live format rendering, file-promise receipt, and complete ClipboardPublication validation remain their separately tracked Validation Contract slices.

## Review

Independent Standards and Spec reviews both found that the initial adapter hid itself on rejection, bypassing workflow-owned state. Destination completion now emits a `DropWorkflow.destinationInteractionEnded` event and the coordinator alone renders the resulting request. The Standards review's smaller duplication, data-clump, and naming findings were also resolved. The Spec review identified premature clipboard publication and Space/full-screen policy; those changes were removed and left to issues #20 and #17 respectively.
