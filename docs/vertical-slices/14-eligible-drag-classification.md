# Vertical Slice #14: Eligible Drag classification

## Public seams and behavior

Issue #1 pre-agrees `DragClassifier` and `DropWorkflow` as the classification and interaction seams. Issue #14 supplies this slice's acceptance criteria.

`DragClassifier.classify` consumes immutable value descriptors and returns eligible, ineligible, or indeterminate without filesystem access, promise fulfillment, AppKit objects, or permission requests. The descriptor preserves the complete item inventory and each promised file; alternate pasteboard representations of one item are not additional items. Content evidence distinguishes explicit HEIC from known non-HEIC and missing/generic types. A case-insensitive `.heic` file extension or explicit HEIC content evidence establishes eligibility for a single file URL. Contradictory evidence, non-file URLs, multiple/mixed items, and non-HEIC items are rejected. Missing inventories, extensionless files with unknown content, and promises with unavailable count/type remain indeterminate.

`DragClassifier.acceptDrop(atDestination:input:optionHeld:)` requires a fresh snapshot on release at the Drop Zone. It reclassifies that snapshot and binds a URL descriptor to the matching input. For an eligible promise, the input owner must finish receipt first and provide its local materialized input; conflicting filename evidence is rejected. Only this factory can construct `AcceptedDrop`; early eligibility results cannot be passed to the conversion workflow as authority. The eventual destination adapter remains responsible for supplying fresh destination evidence and associating a received promise with its input. The converter still validates actual readable image content.

`DropWorkflow.dragObserved` changes only the workflow-owned `isDropZoneRequested` state. It emits no conversion effects and does not change an active Accepted Drop's identity. Acceptance clears the presentation request. The coordinator exposes this state and forwards observations without inferring eligibility. Full presentation lifecycle, mouse monitoring, and promise receipt/cleanup remain separate slices.

## Red → green evidence

Each numbered test was added before its production behavior. Focused test commands compiled and typechecked the application and test targets.

1. `DragClassifierTests/singleExplicitHEICFileURLIsEligible`: build failed for missing `DragDescriptor`/`DragClassifier`; the initial descriptor and classifier passed the focused suite.
2. `DragClassifierTests/explicitHEICTypeIsEligible`: build failed for missing `filePromise`; single-promise and explicit content-type support passed the suite.
3. `DragClassifierTests/rejectsMultipleMixedNonHEICAndContradictoryItems`: build failed for missing `other`; adding non-file items and conservative URL/content checks passed the parameterized rejection matrix.
4. `DragClassifierTests/ambiguousEvidenceRemainsIndeterminate`: assertions failed for extensionless unknown content and promises with unavailable count/type; returning indeterminate passed the suite.
5. `DragClassifierTests/onlyEligibleDestinationEvidenceCreatesAnAcceptedDropForTheMatchingInput`: build failed for missing `acceptDrop`; the destination factory, restricted initializer, and migrated existing conversion tests passed classifier, workflow, and coordinator suites together.
6. `DropWorkflowTests/earlyObservationRequestsPresentationWithoutAuthorizingOrReplacingConversion`: build failed for missing `dragObserved`/`isDropZoneRequested`; workflow-owned presentation state passed the focused workflow suite, including preservation of in-flight conversion and its handoff.

Focused invocation (replace the suite selector as above):

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Dropshot14Tests \
  -only-testing:DropshotTests/DragClassifierTests
```

Temporary logs: `/tmp/dropshot14-red1-authorized.log`, `/tmp/dropshot14-red2.log` through `red6.log`, and `/tmp/dropshot14-green1.log` through `green6.log`. The initial sandboxed invocation could not access Xcode system services and is excluded; tests subsequently ran with test-service access.

## Complete suite and typechecking

On 2026-09-04, macOS 26.6.2 (25G83), arm64 MacBook Pro, Xcode 26.6:

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Dropshot14Tests
```

All unit cases and both UI launch/smoke cases passed. The existing `DropshotUITests/testLaunchPerformance()` failed with Xcode's “Received unexpected number of metrics: 0 in iteration with index 2. Got 1 in iteration with index 0.” The full invocation exited 65; its result bundle reports 51 passing test runs and one failure. Log: `/tmp/dropshot14-full.log`.

Reran only that failed test using `-only-testing:DropshotUITests/DropshotUITests/testLaunchPerformance`: exit 0, test passed in 12.645 seconds (measurement iterations, not single-launch duration). Log: `/tmp/dropshot14-launch-retry.log`. No test assertions or thresholds were changed. All tests have passing evidence across the full run and isolated retry; the first full invocation was not a clean pass. No Swift compiler warnings were reported.

This pure classification slice performs no I/O, conversion, or rendered presentation. It does not establish the real-system drag compatibility, presentation latency, promise lifetime, or Release Artifact gates from the Validation Contract.

## Review

The implement skill's code-review step ran two independent agents against `git diff --cached dc682ef57a5a6d16613fb25a39b7cc115b4a466f` before commit. Standards: no documented-standard breaches or actionable smell findings. Spec: no missing requirements, incorrect behavior, or scope creep within issue #14.
