# Diorama architecture

## The box is a display

`VirtualDisplayController` creates one `CGVirtualDisplay` with a fixed vendor, product and serial number, so macOS recognises it across launches and keeps its wallpaper, arrangement and chosen resolution. The display advertises a set of Retina modes (`StageResolution.all`) and the controller switches between them with `CGConfigureDisplayWithDisplayMode`; changing resolution never recreates the display. The display exists only while the process holds the object; macOS removes it on quit and moves any windows left on it to a remaining display.

The classes come from CoreGraphics but are not in the SDK. `Sources/CGVirtualDisplayShim/include/CGVirtualDisplay.h` declares just the members Diorama uses, with 32-bit integer property types matching the framework's own. Every declaration there is an ABI assumption to re-check on new macOS releases.

## The stage is a capture

`StageStream` runs an `SCStream` over the virtual display at its native pixel size with the cursor included. `StageFrameSink` receives sample buffers on a capture queue, keeps only complete frames, and hands the newest one to the main thread while dropping frames if one is still pending. `StageNSView` puts the frame's `IOSurface` straight into its layer's `contents` with aspect-fit gravity, so no copies are made. The frame keeps its `CMSampleBuffer` alive so ScreenCaptureKit does not recycle the surface while it is on screen.

The view also reports where the picture actually is: after every move, resize, screen change, occlusion or key change it aspect-fits the display's point size into its own screen rectangle, converts that to global top-left coordinates, and passes the result to the model as the *stage* rectangle (or `nil` while it is not visible).

## The pointer is fenced

`CursorFence` in `DioramaCore` is a pure state machine; `InputBridge` feeds it every pointer event from a HID-level `CGEventTap` and applies its decisions. Keeping the policy pure means the whole interaction can be tested without a window server.

- **Free.** If an event's location lands inside the virtual display, the fence rewrites it to the nearest point on a physical display and warps the cursor there. If the location lands inside the stage rectangle, the stage window is the topmost window at that point, interaction is on and the fence is *armed*, the pointer is captured: the event is rewritten to the matching point on the virtual display and the cursor is warped there.
- **Captured.** The fence remembers a *shadow* — where the person believes the pointer is on their physical screen — and the *target* where it last placed the cursor on the display. Each event's offset from the target is the hardware movement since then; it moves the shadow one to one, the shadow is mapped back onto the display, the event is rewritten and the cursor warped to that point. Leaving the stage rectangle, another window covering the stage, interaction being switched off, or pushing against an edge of the virtual display (cursor pinned at the edge with the raw delta still pointing outward) releases the pointer: the cursor is warped to the shadow, clamped to a physical display, and placed one point outside the picture when it left by pushing.
- **Armed.** After a release the fence stays disarmed until it sees the pointer outside the stage rectangle, so a release at the picture's edge does not immediately re-capture.

Every warp is followed by `CGAssociateMouseAndMouseCursorPosition(true)`, which cancels the brief suspension of hardware events that macOS applies after a warp. The tap is re-enabled if macOS disables it for taking too long. Hotkeys are matched in the same tap (Control-Option-Command plus a letter) and consumed so no application sees them.

## Windows move through Accessibility

`WindowMover` reads the frontmost application's focused window and every regular application's windows through `AXUIElement`, with a short messaging timeout so an unresponsive application cannot stall the UI. A window is "in Diorama" when its top-left corner lies inside the display bounds. Moving keeps the window's size when it fits and centres it on the destination display.

## Screenshots

`Screenshots` uses `SCScreenshotManager` on the same content filter as the stream, at full pixel resolution and without the cursor, and encodes PNG with ImageIO. Files go to `~/Pictures/Diorama` with the macOS screenshot naming pattern produced by `ScreenshotNaming`.

## Application boundary

Diorama runs outside App Sandbox by necessity: an active session-wide event tap, Accessibility control of other applications' windows, and the private display classes all require it. The bundle is signed with hardened runtime and no entitlements. It has no helper processes, no network access and no third-party code. Screen Recording and Accessibility permissions are requested at launch and polled once a second until granted; the capture and the tap start as soon as each is available.

## Validation

`make test` runs the core tests: aspect fitting, coordinate mapping, clamping, every fence transition (capture, one-to-one tracking, release by leaving, release by pushing, re-arming, stage disappearing, explicit release), hotkey matching, screenshot naming and resolution invariants. `scripts/verify-app.sh` checks the bundle signature, metadata and external library references.

## Open verification

The first build of this repository was authored without access to a macOS toolchain, so the following need confirming on a real Mac before the behaviour is trusted:

1. The package compiles cleanly under Swift 6 strict concurrency (`make test`, `make build`).
2. `CGVirtualDisplay` creation succeeds on the installed macOS and the display appears in System Settings › Displays with the offered Retina modes.
3. Rewriting a pointer event's location in a HID-level tap, combined with `CGWarpMouseCursorPosition`, places the cursor where the fence intends without visible drift while captured; if the cursor drifts, warp on every event only (drop the location rewrite) or vice versa in `InputBridge.apply`.
4. Pushing against a non-adjacent edge of the virtual display reports a non-zero raw delta while the cursor is pinned, so the push release fires.
5. ScreenCaptureKit delivers frames for the virtual display at 60 Hz with the cursor drawn while it is captured.
