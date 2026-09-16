# Vertical Slice #18: File-promise Accepted Drops

## Public seams and ownership

Parent issue #1 pre-agrees `DroppedInput` for resource lifetime and `DropWorkflow` for interaction behavior. Issue #18 adds operation-owned promise receipt to the same Accepted Drop path used by file URLs.

The destination adapter retains a single HEIC `NSFilePromiseReceiver` only at release. Observations and hover classification never fulfill promises. Destination classification creates the Accepted Drop before receipt, preserving release-time format selection and assigning the workflow generation before any asynchronous wait. The coordinator asks `DroppedInput` for a readable file, passes that file to the existing converter, and reports completion using the original generation. Cancellation prevents Clipboard Handoff even if a converter returns success.

`DroppedInput` owns balanced security-scoped access for file URLs and receipt into a unique child of its owned temporary parent for promises. The converter retains no source lifetime responsibilities. Launch cleanup runs before drag observation starts and is limited to the owned temporary parent.

## Scope and release evidence

Issue #20 still owns connecting the running application's Accepted Drop callback to the production clipboard adapter; the existing application callback remains dismiss-only. This slice establishes the promise path through the injectable coordinator and destination adapter. Issue #21 owns the wider overlapping-drop completion matrix and active cancellation policy.

Real cross-application promise drags and signed sandbox Release Artifact checks remain release gates. Automated tests do not establish those platform compatibility guarantees.

## Coordinator regression evidence

- With the original direct conversion call, `cancelledAcceptedDropNeverPublishes` failed while the five existing coordinator tests passed (`/tmp/dropshot18-coordinator-red.log`).
- With promise receipt absent from the coordinator, the real-fixture `promisedHEICUsesTheAcceptedDropConversionAndCleansItsInput` regression also failed (`/tmp/dropshot18-promise-red.log`).
- Wrapping conversion in `DroppedInput.withReadableFile` and checking cancellation before completion made all seven coordinator tests pass (`/tmp/dropshot18-coordinator-green.log`). The promise test verifies actual PNG bytes from the HEIC fixture, removal of the operation directory, and preservation of the original source.

Focused command:

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Dropshot18Tests \
  -only-testing:DropshotTests/DropCoordinatorTests
```

## AppKit validation boundary

The installed SDK's `NSFilePromiseReceiver.h` documents that `fileNames` is empty before receipt is called in and that the reader executes on the supplied operation queue, including error callbacks for failed/cancelled writes. The adapter validates the complete filename inventory in that reader callback and forwards late callbacks to the input owner for cleanup.

A synthetic `NSFilePromiseProvider` on a named pasteboard returned an empty filename inventory immediately after `receivePromisedFiles`. Attempting receipt outside a real drag session then remained pending beyond 25 seconds and was stopped. This is not passing delivery evidence. The retained adapter test checks pending input creation and absence of early fulfillment; real receipt requires a manual cross-application drag check. No arbitrary receipt timeout was added. Task cancellation ends the owned operation, and a later callback cleans up again.

## Resource and adapter coverage

`DroppedInputTests` exercises direct-source preservation, balanced scoped access on success and failure, promise success and receipt/body failures, cancellation followed by a late callback that recreates its directory, outside/symlink input rejection, launch cleanup preserving unrelated files, and rejection of a second concurrent read without deleting the first operation's input. The symlink-root test uses an isolated fixture containing both the owned root and unrelated marker files.

The classifier/snapshot focused suite passed 26 test runs with no compiler warnings. Pending promises cannot be paired with file-URL evidence, and the destination adapter preserves authoritative single-item checks.

## Review

Independent Standards and Spec reviews compared the change to `2d3513c958de67a7523a21a7c0ee3d3f79d8f3a4`. Standards review led to attempting all abandoned children before reporting a cleanup error. Spec review added a cancellation check immediately before synchronous clipboard publication, terminating the matching workflow generation. Both reviewers reported no remaining actionable findings after recheck. Live AppKit promise receipt remains the validation limitation described above.

## Final verification

The focused `DroppedInputTests` suite passed all eight cases with no compiler warnings (`/tmp/dropshot18-input-owner.log`).

On 2026-09-15, macOS 26.6.2 (25G83), arm64 MacBook Pro, Xcode 27.0 (27A266a):

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Dropshot18Tests
```

Result: exit 0. The result bundle reports 59 tests and 91 runs including dynamic parameters, with zero failures, zero skips, and no runtime warnings. Unit tests, UI smoke/launch tests, and launch-performance tests all passed. No Swift compiler warnings or errors appeared. Log: `/tmp/dropshot18-full.log`; result bundle: `/tmp/Dropshot18Tests/Logs/Test/Test-Dropshot-2026.09.15_17-39-50--0700.xcresult`. `git diff --check` passed. These are development-host results, not signed sandbox Release Artifact evidence.
