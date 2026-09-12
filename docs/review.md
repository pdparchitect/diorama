# Alignment review — 12 September 2026

Diorama had a sound small-app layout but remained a prototype with gaps in its lifecycle and verification. The existing uncommitted private-display ABI, Retina-mode, pointer-warp, window-casting, and layout fixes were preserved and incorporated.

## Comparison

The review used the smaller sibling macOS projects; Noodle was excluded.

| Reference | Established pattern | Diorama outcome |
| --- | --- | --- |
| Runbar | Swift package, tested core, `dist` bundle, Make targets, hardened runtime, icon master and ICNS | Kept that layout and made verification inspect the actual shipped boundary. |
| ModRadio, MessagesClone | Release builds, native UI, isolated build output, signed app resources | Release is now the default; setup and errors use native SwiftUI controls. |
| Puter | Explicit app lifecycle, bundle-contained dependencies, polished material icon | Added explicit single-window lifecycle and removed Xcode-only runtime search paths. |
| Runbar, GoalTracker, ModRadio, Puter | Sculpted macOS icon with clear silhouette, physical materials, and controlled highlights | Generated a titanium desktop shadowbox, retained real alpha, and rebuilt all ICNS sizes. |
| Sandboxed sibling apps | Entitlements tied to actual capabilities | Preserved Diorama's existing unsandboxed design for its global input tap and Accessibility window control. No additional entitlements, helpers, or runtime dependencies. |

## Corrections

- Screen Recording and Accessibility setup precedes display creation. Revocation removes the display; a blank or failed capture cannot take the pointer into an unseen stage.
- The stage retains its current capture buffer. Session generations reject late callbacks and startup completions; unexpected stops clear running state and allow retry.
- Hotkey actions leave the event-tap callback before window operations run. Autorepeat does not trigger repeated screenshots or window moves. Geometry changes release the old pointer mapping.
- Toolbar and menu window actions use the last active application. The return action also avoids choosing Diorama's own display if it has been made the main display.
- Same-second screenshot saves use exclusive creation with suffixes. Clipboard encoding happens before clearing the previous content.
- The private display initializer is nullable and mode-configuration failures cancel their transaction.
- Build output is staged and verified before replacement. Installation replaces the complete bundle, verifies source/staged/destination copies, and refuses unrelated apps and symlinks.
- CI archives the app as a ZIP to preserve executable permissions. Documentation no longer promises dragging through a fenced screen edge or app-menu integration that Diorama does not implement.
- ScreenCaptureKit imports account for the macOS 15 SDK's missing concurrency annotations; shareable-content snapshot access stays on the main actor. This was caught by CI using Xcode 16.4, independently of the newer local SDK.
- Plain primary clicks on empty stage wallpaper are swallowed together with their drag and release events. This prevents the macOS reveal-desktop action from affecting physical displays; app clicks and desktop context menus pass through.
- Saved screenshots open explicitly in Preview. The pointer is released first; if Preview cannot open, Finder reveals the successfully saved file. Copy Screenshot remains available for direct clipboard capture.

## Validation

On macOS 26.6.2 with Apple Swift 6.3.3:

- 33 tests pass: 28 core tests plus five app regressions covering capture failure/retry, stop during startup, superseded startup, failed startup cleanup, and screenshot collisions. Seven core tests cover wallpaper gesture pairing, dragging out of the stage, unfiltered physical and app clicks, secondary buttons, and Control-click context menus.
- Debug test build and optimized release build pass. Strict signature checks confirm hardened runtime, an empty entitlement set, one Mach-O executable, system framework/runtime dependencies, and the expected icon and metadata. No helper executable is embedded.
- The release bundle launches and its permission setup screen, disabled unavailable toolbar actions, and new icon were inspected through the native UI. Neither permission was granted during this review.
- Installation into an isolated project build folder is verified, including replacement that removes obsolete bundle files and refusal of an unrelated app or symbolic link.
- The PNG master has a real alpha channel; the native ICNS conversion succeeds. Runbar has Diorama **Build & Launch** and **Run Tests** entries.

The earlier private-display creation and Retina-mode observations are retained in `architecture.md` as historical evidence. End-to-end ScreenCaptureKit frames, window movement, keyboard focus, edge release, pointer drift, resolution changes during interaction, permission revocation during capture, and physical-monitor changes still need a hands-on pass with both permissions granted. The private CoreGraphics API remains a macOS compatibility constraint. The automated session tests validate lifecycle handling, not WindowServer behavior.

## Interaction follow-up

After the user renewed permissions, the live stage was observed streaming. macOS's TCC log showed that the earlier permissions mismatch came from the saved code requirement no longer matching a rebuilt ad-hoc executable, despite the Settings toggles remaining enabled. No privacy preferences were reset by the review.

The user confirmed that only empty wallpaper clicks triggered Show Desktop. A read-only WindowServer/AppKit diagnostic on the running virtual display confirmed that its empty wallpaper returns window number zero from the native mouse-down hit test; menu extras have separate windows. The gesture guard is covered by the new tests. Rechecking the updated tap with real clicks and the complete capture-to-Preview action requires relaunching the updated app; ad-hoc rebuilds may require renewed permission grants.

The purple screen-sharing menu is macOS UI attached to active capture streams, as described in [Apple's ScreenCaptureKit session](https://developer.apple.com/videos/play/wwdc2023/10136/). The SDK provides a whole-menu-bar capture filter but no documented switch targeting that indicator alone. The full-desktop capture retains the menu bar.

## Stable local signing

The build originally defaulted to ad-hoc signing. A check with normal Keychain access found an existing valid Apple Development identity, which is now pinned in this checkout's local `diorama.signingIdentity` Git setting. No certificate or private key is stored in the repository. Local builds require a configured identity and do not fall back if it is unavailable; CI explicitly opts into disposable ad-hoc artifacts.

The rebuilt release passes strict signature and bundle verification with the Apple certificate, hardened runtime, and no entitlements. A separately signed debug executable has a different CDHash but exactly the same designated requirement, and passes validation against the release's requirement. Re-signing that temporary copy ad-hoc fails the same requirement check. Missing signing configuration and a locally configured ad-hoc fallback both fail before compilation. These temporary copies were never launched.

The transition from the old ad-hoc identity still requires a fresh permission grant. Grant retention across subsequent user launches remains a live TCC check; the identity comparison verifies that future code changes no longer inherently replace the app's designated requirement. The existing macOS access boundary and privacy settings are unchanged. [Apple documents designated requirements and identity tracking here.](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)
