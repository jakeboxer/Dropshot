# Packaging, signing, and release capabilities

## Question

What exact packaging, signing, notarization, local-distribution, temporary-input, and launch-at-login contract should Dropshot use for its macOS 26 Apple-silicon MVP, and what evidence proves that two consecutive releases request neither Accessibility nor Input Monitoring and have no broad filesystem access?

## Recommendation

Ship Dropshot as an **arm64-only, sandboxed, Developer ID-signed and notarized `.app` inside a notarized DMG**. Keep the hardened runtime at its default strictness, with no exceptions. The release executable should have only these entitlements:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

The user-selected read-only entitlement is the narrow capability appropriate to source images explicitly supplied by the user. Do not add Downloads, Pictures, Music, Movies, all-files, Apple Events, automation, camera, microphone, Photos-library, or hardened-runtime exception entitlements. In particular, release signing must not retain `com.apple.security.get-task-allow=true`.

The MVP should use AppKit drag-and-drop and `NSFilePromiseReceiver`, not global event taps or Accessibility APIs. Read Option-key state from the app's drag events rather than globally monitoring keyboard events. Write promised files only into a unique per-operation directory below `URL.temporaryDirectory`, delete the directory on every terminal path, and delete abandoned Dropshot-owned operation directories at next launch.

Use `SMAppService.mainApp.register()` and `.unregister()` for the user-facing “Launch at Login” choice. Reflect `SMAppService.mainApp.status`, including `.requiresApproval`, in the UI. Do not install a legacy LaunchAgent for this main-app use case.

This is intentionally a direct-distribution contract, not a Mac App Store contract. App Sandbox is optional for Developer ID distribution, but choosing it makes the narrow filesystem claim enforceable and testable rather than merely aspirational. [Apple describes App Sandbox as limiting access to system resources and user data through entitlements](https://developer.apple.com/documentation/security/app-sandbox), and separately says that a directly distributed notarized app must use hardened runtime while sandboxing is optional. [Preparing your app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)

## Bundle and build settings

Use the following Release configuration:

| Setting / key | Release value | Reason |
| --- | --- | --- |
| `PRODUCT_BUNDLE_IDENTIFIER` / `CFBundleIdentifier` | `com.jakeboxer.Dropshot` | Stable application and code-signing identity; retain it across updates. |
| `PRODUCT_NAME` | `Dropshot` | Produces `Dropshot.app` and a consistent executable/display name. |
| `MARKETING_VERSION` / `CFBundleShortVersionString` | Release version | User-visible version; change when releasing a new product version. |
| `CURRENT_PROJECT_VERSION` / `CFBundleVersion` | Unique, monotonically increasing build | Apple says to increment the build version before distributing each macOS build. [CFBundleVersion](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion) |
| `MACOSX_DEPLOYMENT_TARGET` / `LSMinimumSystemVersion` | The exact supported macOS 26 point release; currently `26.5` in the project | The issue's macOS 15 wording is stale. Do not lower the signed artifact to 15. |
| `ARCHS` | `arm64` for Release | Apple silicon is the map's declared platform; verify the artifact rather than relying only on build settings. [Building a universal macOS binary](https://developer.apple.com/documentation/Apple-Silicon/building-a-universal-macos-binary) |
| `ONLY_ACTIVE_ARCH` | `NO` for Release | Avoid an accidental developer-machine-only build convention. |
| `INFOPLIST_KEY_LSUIElement` / `LSUIElement` | `YES` | Apple defines this as an agent app that does not appear in the Dock. [LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement) |
| `ENABLE_APP_SANDBOX` | `YES` | Enforces the narrow filesystem capability set. |
| `ENABLE_HARDENED_RUNTIME` | `YES` | Required for notarization. [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime) |
| Signing method | Developer ID Application, secure timestamp | This certificate signs Mac apps distributed outside the Mac App Store. [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates) |

Xcode's generated Info.plist can remain in use. The resulting bundle must contain correct `CFBundleExecutable`, `CFBundleIdentifier`, `CFBundleName`, `CFBundlePackageType`, `CFBundleShortVersionString`, `CFBundleVersion`, `LSMinimumSystemVersion`, and `LSUIElement` values. [Apple's Info.plist guidance](https://developer.apple.com/documentation/bundleresources/managing-your-app-s-information-property-list)

Do not enable `REGISTER_APP_GROUPS` unless an App Group is actually introduced; Dropshot's current single-process design does not require one. No Developer ID provisioning profile is needed for the unrestricted App Sandbox and hardened-runtime entitlements alone; Apple documents those categories as unrestricted on macOS. [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)

## Filesystem and temporary-input contract

`com.apple.security.files.user-selected.read-only` grants read-only access to files the user selects; do not request its read-write form because Dropshot never modifies its source. [User-selected read-only entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-only)

Direct file URLs from a drag are consumed read-only. File promises are received through `NSFilePromiseReceiver.receivePromisedFiles(atDestination:...)` into a Dropshot-owned destination. Apple explicitly presents `NSFilePromiseReceiver` as the receiver for promised drag files, including drags from Photos, and recommends a background operation queue for fulfillment. [NSFilePromiseReceiver](https://developer.apple.com/documentation/appkit/nsfilepromisereceiver) and [Apple's file-promise sample](https://developer.apple.com/documentation/appkit/supporting-table-view-drag-and-drop-through-file-promises)

For each Accepted Drop that needs materialization:

1. Create a randomly named directory beneath `URL.temporaryDirectory`, optionally under a stable `Dropshot-EphemeralInputs` parent.
2. Give that directory to the file-promise receiver.
3. Reject unexpected additional files and validate the fulfilled item as the single expected HEIC before decoding it.
4. Remove the whole per-operation directory immediately after success, cancellation, or failure, using a `defer`/single cleanup owner so terminal paths cannot diverge.
5. At startup, enumerate only the Dropshot-owned parent and remove abandoned per-operation children. Never enumerate or clean the general temporary directory.

Apple says `URL.temporaryDirectory` is inside the app's sandbox container for a sandboxed macOS app. Apple also warns not to depend on a temporary directory surviving app exit and recommends deleting it after use. [URL.temporaryDirectory](https://developer.apple.com/documentation/foundation/url/temporarydirectory) and [FileManager temporary-directory guidance](https://developer.apple.com/documentation/Foundation/FileManager/url%28for%3Ain%3AappropriateFor%3Acreate%3A%29)

Do not write runtime state into `Dropshot.app`; modifying signed bundle contents invalidates the seal. [TN2206: macOS Code Signing In Depth](https://developer.apple.com/library/archive/technotes/tn2206/)

## Launch at login

Use the Service Management framework available well before the macOS 26 deployment target:

```swift
let service = SMAppService.mainApp
try service.register()     // opt in
try service.unregister()   // opt out
```

Apple defines `mainApp` as the service corresponding to the main application as a login item. Registration makes the main app launch at subsequent logins, subject to user approval. [SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) and [register()](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29)

Treat `.enabled` as active, `.notRegistered` as off, and `.requiresApproval` as registered but awaiting or having lost user consent; direct the user to Login Items settings only in the last case. [SMAppService status: requiresApproval](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval)

Because this registers the signed main app by identity, version-update testing must install both versions at the same `/Applications/Dropshot.app` path with the same bundle identifier and Developer ID team/designated requirement.

## Signing, notarization, and packaging pipeline

1. Archive Release for a Mac destination and export using Xcode's **Direct Distribution** / Developer ID workflow, or an equivalent scripted export. Apple describes Direct Distribution as the recommended macOS path for notarizing a Developer ID app. [Distributing your app for beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
2. Sign nested code from the inside out and the outer app last using the **Developer ID Application** identity, hardened runtime, and a secure timestamp. For a simple app with no nested executable code, this is just the app. Do not use Developer ID Installer unless later shipping a flat installer package. [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)
3. Verify the exported app before packaging.
4. Create a read-only UDIF DMG containing `Dropshot.app` and an `/Applications` convenience link. Do not add an installer or privileged helper.
5. Submit the final DMG with `xcrun notarytool submit Dropshot.dmg --keychain-profile <profile> --wait`.
6. Require `Accepted`, save the submission ID, and fetch/save the JSON log with `notarytool log`; Apple recommends checking the log even after success.
7. Because a DMG submission generates tickets for the top-level image and nested code, staple and validate both artifacts: `xcrun stapler staple Dropshot.app`, `xcrun stapler validate Dropshot.app`, then staple and validate the final `Dropshot.dmg`. If packaging changes after submission, resubmit the changed final DMG.

Apple accepts UDIF disk images, signed flat packages, and ZIPs. A ZIP cannot itself be stapled, which is why DMG is the clearer offline-verifiable local artifact. [Customizing the notarization workflow](https://developer.apple.com/documentation/Security/customizing-the-notarization-workflow)

Apple's notarization prerequisites are a valid Developer ID signature on all executables, hardened runtime, secure timestamp, no true `get-task-allow`, an adequate SDK, and well-formed entitlements. [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## Release-blocking artifact checks

Run these checks on the extracted app from the exact DMG that will ship, not on a Debug product or archive intermediate:

```sh
APP="/Applications/Dropshot.app"
BIN="$APP/Contents/MacOS/Dropshot"

lipo -archs "$BIN"                         # exactly: arm64
plutil -p "$APP/Contents/Info.plist"       # expected ID, versions, min OS, LSUIElement
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --verbose=4 "$APP"      # Developer ID identity, TeamIdentifier, runtime flags
codesign --display --entitlements :- "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"

hdiutil verify Dropshot.dmg
xcrun stapler validate Dropshot.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 Dropshot.dmg
```

Store the command output, the exact DMG hash, the notary submission ID, and its JSON log as release evidence. Fail if the effective entitlement set differs from the two-key allowlist above, if `get-task-allow` is true, if any executable is not arm64, or if any signature, Gatekeeper, stapler, or notarization check is not successful. Apple recommends `codesign --verify --deep --strict` to mimic Gatekeeper's recursive checks and documents `spctl` assessment of disk images. [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/)

## Two-version privacy and update validation

Entitlement inspection alone cannot prove the full privacy promise. Accessibility and Input Monitoring consent are initiated by API use, while a non-sandboxed process can read many ordinary paths without a file entitlement. The proof therefore combines sandbox enforcement, static inspection, and clean-state behavior.

Prepare independently signed, notarized, stapled candidate DMGs for version A and version B. Both must use the same bundle identifier, Team ID, and designated requirement, with B carrying a greater `CFBundleVersion`. Apple explains that designated requirements identify code across versions, and Apple warns that differing designated requirements between versions can cause sandbox-container access prompts. [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/) and [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)

Run on a clean macOS 26 Apple-silicon VM snapshot or clean local test account:

### Version A, clean install

1. Acquire the exact release DMG through a quarantine-producing path (for example, browser download or AirDrop), mount it, drag Dropshot to `/Applications`, eject it, and launch the installed copy. Do not test by launching inside the DMG.
2. Run all artifact checks above and archive the evidence.
3. Record that Dropshot is absent from Privacy & Security > Accessibility, Input Monitoring, Files & Folders, and Full Disk Access before exercising the app.
4. Exercise every MVP path: Finder file URL; a file promise from Photos or another promised-file source; JPEG and Option-held PNG; cancellation; invalid input; conversion failure; overlapping drops; Clipboard Handoff; quit/relaunch cleanup.
5. Confirm no privacy-consent prompt occurred and Dropshot remains absent from those four settings panes.
6. Confirm each operation directory is removed after every terminal path. Force-quit during promise receipt, relaunch, and confirm only abandoned Dropshot-owned temporary inputs are removed.
7. Enable Launch at Login, confirm `SMAppService.mainApp.status == .enabled`, log out/in, and confirm one installed Dropshot instance starts.

### A-to-B in-place update

1. Without resetting the sandbox container or login-item state, install B over `/Applications/Dropshot.app` from B's quarantined DMG.
2. Confirm B launches without a sandbox-container identity prompt, retains the user-visible Launch at Login preference, reports the service enabled, and launches exactly once after another logout/login.
3. Repeat all MVP and temporary-cleanup paths, then repeat the four-pane absence check and confirm no privacy-consent prompt occurred.
4. Archive B's artifact checks, privacy screenshots/log, effective entitlements, and notary record separately from A.

### Version B, fresh install

Repeat A's clean-install procedure for B on a second clean account or restored VM snapshot. This distinguishes update-only state from the permissions and behavior of the current artifact.

No source or binary may call `AXIsProcessTrustedWithOptions` or other Accessibility client APIs. Apple documents that `kAXTrustedCheckOptionPrompt` can prompt an untrusted process. [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)

No source or binary may call `CGPreflightListenEventAccess`, `CGRequestListenEventAccess`, or install a global `CGEvent` tap for Option-key observation. Apple provides those APIs specifically for listening-event access, and event taps may be denied when not permitted. [CGPreflightListenEventAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess%28%29), [CGRequestListenEventAccess](https://developer.apple.com/documentation/CoreGraphics/CGRequestListenEventAccess%28%29), and [CGEventTapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29)

The clean-state checks can be made repeatable by resetting protected-resource decisions for the app between test runs where necessary; use Apple's documented macOS protected-resource reset procedure rather than manually editing the TCC database. [Resetting access to protected resources in macOS](https://developer.apple.com/documentation/xcode/resetting-access-to-protected-resources-in-macos)

## Decision

The capability boundary is: sandboxed app; read-only access only to user-selected drag inputs; private sandbox temporary storage for promised inputs; clipboard output; main-app launch at login; no other entitlement or privacy-sensitive API. The ship vehicle is an arm64 Developer ID Application-signed, hardened, notarized, and stapled app in a notarized and stapled DMG. Release is blocked until both the clean-install and A-to-B update matrix pass on macOS 26 Apple silicon, including the fresh-B control.

