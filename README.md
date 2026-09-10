# Diorama

**A desktop in a box.**

Diorama creates a second, invisible display on your Mac and shows it live inside a window on your real screen. Put the tools you are working on in there, arrange them once, and they stay exactly as you left them: your own desktop stays clean, the picture is always ready for a screenshot of a complete desktop, and when you move the pointer into the picture you are working inside it for real.

<p align="center"><img src="Support/AppIcon.png" width="200" alt="Diorama application icon"></p>

## How it works

The box is a real display as far as macOS is concerned — it has its own wallpaper, menu bar, Spaces and resolution — but it has no physical screen behind it. Diorama captures it with ScreenCaptureKit and paints the frames into the stage window.

The pointer can never wander onto that display by accident. Diorama fences it off, so the edge of your real screen stays a hard edge. There are three deliberate ways in:

- **Move the pointer into the picture.** While it is inside, it lives on the virtual display: clicks, drags, scrolling and typing all go to the windows in the box, and the picture follows your hand one to one. Move out of the picture, or push against its edge, and the pointer pops back out beside it.
- **Send a window.** Press ⌃⌥⌘D in any application to move its front window into Diorama, ⌃⌥⌘B to bring it back, and ⌃⌥⌘R to return everything. The application's own **Window › Move to Diorama** menu item works too.
- **Drag it there.** The virtual display sits next to your real one in System Settings › Displays. Dragging a window past that edge moves it into the box, even though the pointer itself stays on your screen.

Switch **Stage › Interactive** off (⌃⌥⌘I) for a view-only stage.

## Screenshots

⌃⌥⌘S saves a full-resolution PNG of the whole virtual desktop — wallpaper, menu bar and windows, no cursor — to `~/Pictures/Diorama`, named like macOS screenshots. **Stage › Copy Screenshot** puts the same image on the clipboard. Because the box never changes unless you change it, every screenshot shows the same tidy, complete desktop without rearranging anything on your real screen.

The display offers Retina resolutions from 1024 × 576 to 1920 × 1080 points (2048 × 1152 to 3840 × 2160 pixels) under **Stage › Resolution**. Pick the one that matches the screenshots you want; 1920 × 1080 is the default.

## Requirements and build

macOS 15 or newer, with Xcode Command Line Tools supporting Swift 6. There are no third-party dependencies.

```sh
make test
make build
make install
open /Applications/Diorama.app
```

`make build` creates `dist/Diorama.app`, ad-hoc signed with hardened runtime. `DIORAMA_SIGNING_IDENTITY` selects an installed signing identity and `DIORAMA_BUILD_CONFIGURATION=release` builds optimized binaries. `make run` builds and opens the repository's bundle; `make icon` regenerates `Support/Diorama.icns` from `Support/AppIcon.png`. Set `DIORAMA_INSTALL_DIR="$HOME/Applications"` for a user-local installation. The installer refuses to overwrite an unrelated app and asks you to quit a running Diorama first.

On first launch Diorama asks for two permissions:

- **Screen & System Audio Recording** — to capture the virtual display. macOS applies this after the app is relaunched.
- **Accessibility** — to fence the pointer, route it into the box and move other applications' windows.

Ad-hoc signed builds get a new code signature every time they are rebuilt, and macOS then treats them as a new app for these permissions. Use a stable signing identity for a smoother development loop, or re-grant the permissions after rebuilding.

## Access boundary

Diorama runs outside Apple App Sandbox: it installs a system-wide event tap, moves other applications' windows through the Accessibility API and creates a display using CoreGraphics interfaces that are not part of the public SDK. The `CGVirtualDisplay` classes are declared in `Sources/CGVirtualDisplayShim` and resolved from CoreGraphics at link time; they are the same interfaces used by virtual display utilities such as DeskPad and BetterDisplay, and they may change in a future macOS release.

The event tap only rewrites pointer locations and consumes its own five hotkeys; it does not log or forward keystrokes. Screenshots stay on your Mac. No network access is used.

## Repository layout

```text
Sources/Diorama/                  Stage window, virtual display, capture, pointer bridge, window moving
Sources/DioramaCore/              Stage geometry, pointer fence, hotkeys, resolutions (pure, tested)
Sources/CGVirtualDisplayShim/     Declarations for the private CoreGraphics virtual display classes
Tests/DioramaCoreTests/           Behavioural tests for the core
Support/Info.plist                Application metadata
Support/AppIcon.png               Icon master
Support/Diorama.icns              Multi-resolution application icon
scripts/                          Build, test, install, icon and signature verification
docs/architecture.md              How the pieces fit and what remains to verify
.github/workflows/ci.yml          macOS validation and app artifact
```
