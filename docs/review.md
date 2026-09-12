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

## Validation

On macOS 26.6.2 with Apple Swift 6.3.3:

- 26 tests pass: 21 core tests plus five app regressions covering capture failure/retry, stop during startup, superseded startup, failed startup cleanup, and screenshot collisions.
- Debug test build and optimized release build pass. Strict signature checks confirm hardened runtime, an empty entitlement set, one Mach-O executable, system framework/runtime dependencies, and the expected icon and metadata. No helper executable is embedded.
- The release bundle launches and its permission setup screen, disabled unavailable toolbar actions, and new icon were inspected through the native UI. Neither permission was granted during this review.
- Installation into an isolated project build folder is verified, including replacement that removes obsolete bundle files and refusal of an unrelated app or symbolic link.
- The PNG master has a real alpha channel; the native ICNS conversion succeeds. Runbar has Diorama **Build & Launch** and **Run Tests** entries.

The earlier private-display creation and Retina-mode observations are retained in `architecture.md` as historical evidence. End-to-end ScreenCaptureKit frames, window movement, keyboard focus, edge release, pointer drift, resolution changes during interaction, permission revocation during capture, and physical-monitor changes still need a hands-on pass with both permissions granted. The private CoreGraphics API remains a macOS compatibility constraint. The automated session tests validate lifecycle handling, not WindowServer behavior.
