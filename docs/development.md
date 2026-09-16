# Development

Requires macOS 15 or later and Xcode Command Line Tools with Swift 6. Release packaging runs on Apple Silicon. Swift Package Manager pins Sparkle in `Package.swift` and `Package.resolved`; no other third-party runtime dependency is used.

## Build and run

Select a persistent signing certificate once for this checkout:

```sh
security find-identity -v -p codesigning
git config --local diorama.signingIdentity CERTIFICATE_SHA1
make test
make build
make install
open /Applications/Diorama.app
```

An Apple Development certificate works locally. Its private key stays in Keychain; the selection stays in local Git configuration. `DIORAMA_SIGNING_IDENTITY` overrides that selection. Missing or unavailable identities fail the build. For disposable development artifacts only, explicitly use `DIORAMA_SIGNING_IDENTITY=- make build`; ad-hoc builds can lose macOS permission grants whenever code changes.

`make build` creates `dist/Diorama.app` with hardened runtime. `make run` builds and opens it. Set `DIORAMA_BUILD_CONFIGURATION=debug` for a debug build or `DIORAMA_INSTALL_DIR="$HOME/Applications"` for user-local installation. Quit Diorama before installing. The installer verifies a staged copy before replacement and refuses unrelated apps and symbolic links.

Development builds have update checks disabled so public releases cannot replace local work. `VERSION` supplies both app version fields. Use the [release process](releases.md) for distributable binaries.

## Check changes

`make test` runs the Swift tests and Python release-automation tests. They cover stage geometry, pointer fencing, hotkeys, wallpaper gestures, screenshot naming and collisions, capture cancellation and recovery, version ordering, release notes, artifact integrity, and publication guards. Capture tests use an injected session without recording the screen.

`make verify` checks the actual bundle's signatures, hardened runtime, entitlement grants, executable boundary, dependency paths, update settings, metadata, and icon. Sparkle's framework and two installer executables are signed inside-out with the app's identity. No additional entitlements are granted.

Before distributing changes to capture or interaction, check on a Mac with both permissions granted:

- Live frames and cursor, window movement, typing, dragging, scrolling, and edge release.
- Wallpaper clicks, context menus, view-only mode, and physical-monitor changes.
- Resolution changes, capture failure/retry, and revoking permissions during capture.
- Save-to-Preview, clipboard capture, and quit/relaunch with windows in the stage.

Automated tests do not validate WindowServer behavior. The private CoreGraphics display API must be checked on new macOS releases.

## Layout and assets

| Path | Purpose |
| --- | --- |
| `Sources/Diorama/` | Native app, capture, input, windows, screenshots, and updater |
| `Sources/DioramaCore/` | Pure geometry and interaction policy |
| `Sources/CGVirtualDisplayShim/` | Private CoreGraphics declarations |
| `Tests/` | Swift regressions and release-automation tests |
| `Support/` | App metadata and icons |
| `scripts/` | Build, install, verification, and release tooling |
| `.github/workflows/release.yml` | Validation, release preparation, and publication |

`Support/AppIcon.png` is the transparent icon master. `make icon` uses `sips` and `iconutil` to regenerate the committed `Support/Diorama.icns`; normal builds need no image service. Build outputs, temporary release files, and Python caches are ignored.

Settings follow Noodle's native tab layout and fitted window sizing, with a consistent flat toolbar background. The desktop model uses property-level Observation so background capture and permission polling do not rebuild the settings tab container. Regression tests cover unrelated updates, unchanged values, and preference bindings. `SettingsScrollIndicators.swift` adapts Noodle's macOS 27 resize workaround locally, with the Apache-2.0 license in `Support/Noodle-LICENSE.txt` also included in the app bundle.

Builds and tests use `scripts/swift.sh` to pass the selected Xcode SDK consistently to SwiftPM and the linker. Packaging verifies the executable's linked SDK matches Xcode; an incorrect SDK stamp selects legacy SwiftUI styling and settings behavior even on a newer macOS.

[Documentation](README.md)
