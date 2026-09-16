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

Live evidence is pending. The UI automation tool cannot hold Option across a drag and times out selecting the menu-bar-only Dropshot app. The user has been asked to perform the four real gestures; no synthetic test has been counted as live promise delivery or visual timing evidence.

## Full suite and review

The complete suite passed with exit 0 using `xcodebuild test -quiet -project Dropshot.xcodeproj -scheme Dropshot -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/Dropshot20Full`. Result bundle: `/tmp/Dropshot20Full/Logs/Test/Test-Dropshot-2026.09.15_18-25-24--0700.xcresult`; log: `/tmp/dropshot20-full.log`. Summary: 70 tests, 117 runs including dynamic parameters, zero failures and zero skips. Four runtime priority-inversion warnings point to the existing `ImageConversionTests.swift`; no compiler warnings or errors were reported. This run includes the final clipboard cleanup and multi-item replacement assertions. `git diff --check` passed.

Independent reviews against `a62283fd1b71d69b9d52eb2aa4966e2a9c31c144` found no Standards issues and one remaining Spec acceptance blocker: the live four-case evidence above. An initial sandbox-host concern was withdrawn after checking the actual signed host's entitlements and focused test log. No other missing behavior or scope creep was found. Issue #20 must remain open until the live checks pass; no release-readiness claim is made here.
