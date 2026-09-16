# Vertical Slice #20: Atomic Clipboard Handoff

## Ownership and public seams

Issues #1 and #20 pre-agree `ClipboardPublication` for owned pasteboard integration and `DropWorkflow` for interaction behavior. `ImageConversion` prepares both encoded buffers before returning. `ClipboardPublication` receives those buffers, prepares a single `NSPasteboardItem`, and clears its destination pasteboard only when that item is complete. It publishes the requested JPEG or PNG type plus TIFF without decoding, converting, or manufacturing representations.

The app's destination callback now forwards the authoritatively validated Accepted Drop to `DropCoordinator.accept(_:)`. The coordinator owns conversion, Clipboard Handoff, and the existing 800 ms success effect. Publication errors propagate as failed Clipboard Handoffs and are logged without paths or source details. The later error-experience slice owns richer failure presentation and Last Error.

Preparation failure preserves the previous clipboard. A system publication failure after clearing is reported as failure; the adapter cannot promise restoration of clipboard contents after the pasteboard server rejects a write.

## Automated checks

The clipboard suite checks exact requested bytes, TIFF fallback, one-item replacement, and preservation of existing content on preparation failure. Coordinator integration uses real HEIC conversion and a named pasteboard for both formats, checks success after publication, and confirms that a new drag replaces success and survives the previous dismissal timer. Publication rejection must throw without success presentation.

## Live validation

Issue #20 requires four live cases: file URL and file promise, each with Default Conversion and physical Option-held PNG Format Override. Use the development-only source helper under `tools/` and a known HEIC fixture. A named-pasteboard or injected promise callback test is not evidence of `NSFilePromiseReceiver` delivery.

For each case record the app commit/build, OS, fixture hash, source helper, requested format, one-item pasteboard types, visible success copy and timing, and expected versus actual outcome. For promise cases additionally record the unique Dropshot-owned delivery directory, its removal after completion, and the unchanged original fixture. Release Artifact validation remains separately owned by #28.

## Recorded development validation — 2026-09-15

Environment: Apple silicon, macOS 26.6.2 (25G83), Xcode 27.0 (27A266a). Implementation base: `a62283fd1b71d69b9d52eb2aa4966e2a9c31c144` plus the issue #20 changes in this commit.

The initial clipboard test failed to compile because `ClipboardPublication` did not exist (`/tmp/dropshot20-clipboard-red.log`). Its implementation then passed the five focused clipboard invocations (`/tmp/dropshot20-clipboard-final.log`). The broader focused integration below passed all 15 invocations (including both formats):

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/Dropshot20Integration \
  -only-testing:DropshotTests/DropCoordinatorTests \
  -only-testing:DropshotTests/ClipboardPublicationTests \
  ENABLE_APP_SANDBOX=YES ENABLE_USER_SELECTED_FILES=readonly
```

Result: exit 0, `/tmp/dropshot20-integration.log`; result bundle `/tmp/Dropshot20Integration/Logs/Test/Test-Dropshot-2026.09.15_18-22-50--0700.xcresult`. The signed host's inspected entitlements include App Sandbox and user-selected read-only access. Xcode additionally injects test-manager Mach lookup and filesystem read exceptions; this is adapter integration evidence, not Release Artifact entitlement evidence. The ordinary project defaults remain unchanged. The execution environment needed access to macOS testmanager services outside the agent filesystem sandbox.

A separate normal Debug app was built at `/tmp/Dropshot20Live/Build/Products/Debug/Dropshot.app` using the same sandbox settings and `xcodebuild build`. Its inspected entitlements contain only App Sandbox, user-selected read-only access, and Debug `get-task-allow`, with no test-manager/filesystem exceptions. The build exited 0 without compiler diagnostics.

The [development helper](../../tools/file-promise-drag-source/README.md) compiled and launched successfully as a separate arm64 app. Its bundled `oriented-metadata.heic` matches the repository fixture: SHA-256 `99f191bc015923f27ebc017960786f9ef0da63a59e44e6cbf0e261b809976699`.

At the initial implementation checkpoint, live evidence was pending (completed below). The UI automation tool cannot hold Option across a drag and times out selecting the menu-bar-only Dropshot app. The user has been asked to perform the four real gestures; no synthetic test has been counted as live promise delivery or visual timing evidence.

## Full suite and review

The complete suite passed with exit 0 using `xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Dropshot20Full`. Result bundle: `/tmp/Dropshot20Full/Logs/Test/Test-Dropshot-2026.09.15_18-25-24--0700.xcresult`; log: `/tmp/dropshot20-full.log`. Summary: 70 tests, 117 runs including dynamic parameters, zero failures and zero skips. Four runtime priority-inversion warnings point to the existing `ImageConversionTests.swift`; no compiler warnings or errors were reported. This run includes the final clipboard cleanup and multi-item replacement assertions. `git diff --check` passed.

Independent reviews against `a62283fd1b71d69b9d52eb2aa4966e2a9c31c144` found no Standards issues and one remaining Spec acceptance blocker: the live four-case evidence above. An initial sandbox-host concern was withdrawn after checking the actual signed host's entitlements and focused test log. No other missing behavior or scope creep was found. At that review checkpoint, issue #20 remained blocked on live checks, which are completed below. No Release Artifact readiness claim is made here.

### Live debugging: first successful promise handoff

On 2026-09-15 at 19:20 PDT, the signed sandboxed development app at `/tmp/Dropshot20Live/Build/Products/Debug/Dropshot.app` (commit `d6697fa` plus in-progress live-drag fixes) received a real `NSFilePromiseProvider` drag from the development helper using the unchanged `oriented-metadata.heic` fixture above. The user reported operation `.copy` (`rawValue 1`), one pasteboard item with JPEG=true, PNG=false, TIFF=true, fixture unchanged=true, input exists=false, and operation directory exists=false. The received operation directory was the sandbox temporary `Dropshot-EphemeralInputs/A4E901E3-731D-4B86-861D-35391E7625A3` child. The app trace independently recorded source read, conversion success, clipboard publication, and subsequent dismissal. This establishes live promise delivery, Default Conversion publication, and cleanup; physical Option PNG, file-URL success, and user-observed success timing remain pending.

### File-URL root cause and interaction regressions

The first live attempts exposed two destination-routing bugs: the decorative `NSImageView` registered its own image drag types, and physical mouse-release observation could hide the destination before AppKit called `prepareForDragOperation`/`performDragOperation`. The public panel registration regression failed before unregistering the symbol (`/tmp/dropshot20-arrow-red.log`) and passed afterward (`/tmp/dropshot20-arrow-green.log`). The workflow release-order regression likewise failed before preserving an entered destination through release (`/tmp/dropshot20-release-red.log`) and passed afterward (`/tmp/dropshot20-release-green.log`).

After those fixes, accepted File URL drops still failed to read the source with Cocoa error 257, including inside the synchronous AppKit callback. Identical fixture bytes converted successfully from the app's own bundle, and actual promise delivery also converted and published successfully. Re-signing the helper, moving the fixture outside the helper bundle, and reordering only release-time reads did not fix File URL access.

At 19:22:52 PDT, a controlled probe that avoided **all pre-release `public.file-url` data reads** succeeded: synchronous source read, conversion success, and clipboard publication. The same live path had failed repeatedly when hover/global observation read the URL string. The permanent change therefore separates metadata-only Drag Observation from destination-time URL materialization rather than relaxing sandbox entitlements or changing conversion. The probe's fabricated observation and all temporary tracing must be absent from the final app; this successful probe alone is not final-build validation.


### Permanent drag fix validation

Pre-release observations now carry a metadata-only file reference that can guide eligibility but cannot construct an Accepted Drop. Standard NSURL drags use AppKit's content-type metadata API; only release-time destination evidence materializes the actual scoped URL. Resolved metadata is retained for its pasteboard revision, and completions from a released, stopped, or replaced drag are ignored. The destination remains available through physical release until AppKit delivers its callback; ending a released interaction before deferred acceptance does not suppress the next drag. The helper uses the standard NSURL writer, is ad-hoc signed and verified, and supports captured Copy Results plus Command-C.

The deferred-acceptance regression failed before the lifecycle fix (`/tmp/dropshot20-deferred-red.log`). Metadata movement stability and polled-release regressions failed before caching and pending-detection polling (`/tmp/dropshot20-metadata-red.log`). The combined classifier, snapshot, observer, workflow, and panel suites then passed (`/tmp/dropshot20-drag-green.log`). Lazy pasteboard-provider tests confirm observation does not request file-URL contents, and observed metadata alone cannot authorize conversion.

The full suite passed on the permanent implementation with the sandbox settings below: **81 tests, 131 runs including parameters, zero failures or skips**. Four existing image-conversion QoS runtime warnings remain. Result: `/tmp/Dropshot20Final/Logs/Test/Test-Dropshot-2026.09.15_19-34-50--0700.xcresult`; log: `/tmp/dropshot20-final-full.log`.

```sh
xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Dropshot20Final \
  ENABLE_APP_SANDBOX=YES ENABLE_USER_SELECTED_FILES=readonly
```

The test host retains Xcode's broad read and test-manager exceptions; the separately built live app has only App Sandbox, user-selected read-only, and Debug get-task-allow. All temporary tracing, bundled probe input, and fabricated observations have been removed. Both helper and app were restarted from their verified development paths for the final live checks. The helper fixture still matches the SHA-256 above.

The follow-up Standards review found no domain/ADR violations and requested one shared promise-receiver inventory for destination evidence. The Spec review found no confirmed functional defect or scope creep and identified the then-pending final-build live matrix and visible success feedback; both are now complete below. Both reviews raised metadata API failure as a possible source of indeterminate observation; no transient-failure retry is claimed. This preserves the documented fallible Drag Observation contract without reading source contents early.


### Final-build live results

File URL / Default Conversion passed on the permanent metadata-only implementation (`d6697fa` plus the follow-up changes; `/tmp/Dropshot20Live/Build/Products/Debug/Dropshot.app`). The user observed “Copied” briefly and reported inspection #1, pasteboard changeCount 2725: one item, JPEG=true, PNG=false, TIFF=true, fixture unchanged=true, no promise delivered. The fixed 800 ms duration is covered by the workflow/coordinator tests; the manual observation establishes visible transient feedback, not a stopwatch measurement.

File URL / physical Option Format Override also passed on that build: the user observed “Copied” briefly; inspection #2, pasteboard changeCount 2727 showed one item, JPEG=false, PNG=true, TIFF=true, fixture unchanged=true, no promise delivered.

The review fix materializes promise receivers once for authoritative classification and conversion input. The final snapshot suite passed all 10 tests in `/tmp/Dropshot20PromiseFinal/Logs/Test/Test-Dropshot-2026.09.15_19-38-34--0700.xcresult`. This small follow-up leaves the verified File URL path unchanged. The sandboxed live app was rebuilt and restarted; its final `Dropshot.debug.dylib` SHA-256 is `c88438df41567302274040b419808978799bdea186fbb4d41ec1850664c40f00`.

File Promise / Default Conversion passed on the final promise build: the user observed “Copied”; inspection #3, pasteboard changeCount 2729 showed one item, JPEG=true, PNG=false, TIFF=true, fixture unchanged=true, promised input exists=false, operation directory exists=false. The real delivery directory was `~/Library/Containers/com.jakeboxer.Dropshot/Data/tmp/Dropshot-EphemeralInputs/9EC61DD6-B704-4D0D-9079-900057F7EFA6`.

File Promise / physical Option Format Override passed on the final promise build: the user observed “Copied”; inspection #4, pasteboard changeCount 2731 showed one item, JPEG=false, PNG=true, TIFF=true, fixture unchanged=true, promised input exists=false, operation directory exists=false. Its distinct delivery directory was `~/Library/Containers/com.jakeboxer.Dropshot/Data/tmp/Dropshot-EphemeralInputs/3522418A-B3F0-48B5-88ED-8572612B8BDA`.

All four live source/format cases now pass, each with visible transient success feedback. Real promise delivery and immediate cleanup were confirmed for both formats. The user also confirmed that starting a new drag while “Copied” was visible immediately replaced it with guidance. Deterministic workflow/coordinator tests verify replacement and stale-timer suppression. Publication failure is covered by the injected system-write rejection test with no success presentation.

Final review disposition: the shared promise-receiver finding was fixed and its focused tests passed. The live acceptance blockers are resolved by the four reported cases and the new-drag replacement check. The metadata-failure observation limitation remains explicit above. All issue #20 implementation and validation work is complete; GitHub publication and Release Artifact validation are separate.
