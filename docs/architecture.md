# Diorama architecture

## The box is a display

`VirtualDisplayController` creates one `CGVirtualDisplay` with a fixed vendor, product and serial number, so macOS recognises it across launches and keeps its wallpaper, arrangement and chosen resolution. The display advertises a set of Retina modes (`StageResolution.all`) and the controller switches between them with `CGConfigureDisplayWithDisplayMode`; changing resolution never recreates the display. The display exists only while the process holds the object; macOS removes it on quit and moves any windows left on it to a remaining display.

Three details of the private API matter and were confirmed on macOS 26.6:

- With `hiDPI` set, the modes in `CGVirtualDisplaySettings` are sizes in **points**. macOS backs each with twice as many pixels when that fits `maxPixelsWide × maxPixelsHigh`, and only those modes are usable for the desktop; modes given in pixels come out as 1× modes and their Retina variants are marked unusable. The display comes up in the first listed mode, so the saved preference is listed first.
- `CGDisplayCopyAllDisplayModes` hides Retina modes unless `kCGDisplayShowDuplicateLowResolutionModes` is passed, so the controller always passes it.
- `CGDisplayPixelsWide`/`High` return the size in points for a Retina virtual display. The backing size comes from `CGDisplayCopyDisplayMode`, which the capture stream and screenshots need.

Switching the mode immediately after `applySettings` can fail because the modes are not yet populated; the model retries on its next poll whenever the display is in a mode Diorama does not offer. When macOS restores a mode it remembered from a previous launch, the model adopts it instead.

The classes come from CoreGraphics but are not in the SDK. `Sources/CGVirtualDisplayShim/include/CGVirtualDisplay.h` declares just the members Diorama uses, with 32-bit integer property types matching the framework's own. Every declaration there is an ABI assumption to re-check on new macOS releases.

## The stage is a capture

`StageStream` runs an `SCStream` over the virtual display at its native pixel size with the cursor included. `StageFrameSink` receives sample buffers on a capture queue, keeps only complete frames, and hands the newest one to the main thread while dropping frames if one is still pending. `StageNSView` puts the frame's `IOSurface` straight into its layer's `contents` with aspect-fit gravity, so no copies are made. The view retains the current `StageFrame`, which keeps its `CMSampleBuffer` alive so ScreenCaptureKit does not recycle the surface while it is on screen.

Capture sessions use generation tokens: a late start, frame, or delegate callback from a stopped session cannot revive it or disturb its replacement. Unexpected stops clear the running state, release interaction, and allow a retry. The stage becomes interactive only after its first complete frame.

The view also reports where the picture actually is: after every move, resize, screen change, occlusion or key change it aspect-fits the display's point size into its own screen rectangle, converts that to global top-left coordinates, and passes the result to the model as the *stage* rectangle (or `nil` while it is not visible).

## The pointer is fenced

`CursorFence` in `DioramaCore` is a pure state machine; `InputBridge` feeds it every pointer event from a HID-level `CGEventTap` and applies its decisions. Keeping the policy pure means the whole interaction can be tested without a window server.

- **Free.** If an event's location lands inside the virtual display, the fence rewrites it to the nearest point on a physical display and warps the cursor there. If the location lands inside the stage rectangle, the stage window is the topmost window at that point, interaction is on and the fence is *armed*, the pointer is captured: the event is rewritten to the matching point on the virtual display and the cursor is warped there.
- **Captured.** The fence remembers a *shadow* — where the person believes the pointer is on their physical screen — and the *target* where it last placed the cursor on the display. Each event's offset from the target is the hardware movement since then; it moves the shadow one to one, the shadow is mapped back onto the display, the event is rewritten and the cursor warped to that point. Leaving the stage rectangle, another window covering the stage, interaction being switched off, or pushing against an edge of the virtual display (cursor pinned at the edge with the raw delta still pointing outward) releases the pointer: the cursor is warped to the shadow, clamped to a physical display, and placed one point outside the picture when it left by pushing.
- **Armed.** After a release the fence stays disarmed until it sees the pointer outside the stage rectangle, so a release at the picture's edge does not immediately re-capture.

While captured, only the event location is rewritten: a HID-level event's rewritten location is where the window server puts the cursor, and warping on every event made macOS suppress hardware pointer events for a moment each time, which showed as stutter. The cursor is warped only for the jumps between displays — capture, release and keeping a free pointer off the virtual display — and each warp is followed by `CGAssociateMouseAndMouseCursorPosition(true)`, which cancels that suspension. The tap is re-enabled if macOS disables it for taking too long. Hotkeys are matched in the same tap (Control-Option-Command plus a letter) and consumed so no application sees them. Autorepeat is ignored. Actions are dispatched out of the callback before any Accessibility window queries run; slow applications cannot hold the event tap open. Geometry changes release using the previous mapping, and non-movement events do not supply hardware deltas for edge-push detection.

Before delivering a captured primary mouse-down, `InputBridge` hit-tests its mapped virtual point using `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)`. A zero result identifies empty wallpaper. `WallpaperClickGuard` consumes that down and its matching drag/up events, even if the pointer subsequently leaves the stage, preventing an orphaned gesture from reaching a different window or physical display. Control-click and secondary buttons retain desktop context menus. Ordinary clicks outside the stage are not hit-tested or suppressed. Consumed drags explicitly warp the cursor because there is no delivered event to update its position. This avoids invoking macOS's session-wide reveal-desktop action without changing a global preference.

## Windows move through Accessibility

The model remembers the last activated regular application. `WindowMover` reads that application's focused window when Diorama owns focus, or the frontmost application's focused window when invoked by a global shortcut and every regular application's windows through `AXUIElement`, with a short messaging timeout so an unresponsive application cannot stall the UI. A window is "in Diorama" when its top-left corner lies inside the display bounds. Moving keeps the window's size when it fits and centres it on the destination display.

## Screenshots

`Screenshots` uses `SCScreenshotManager` on the same content filter as the stream, at full pixel resolution and without the cursor, and encodes PNG with ImageIO. Files go to `~/Pictures/Diorama` with the macOS screenshot naming pattern produced by `ScreenshotNaming`. Exclusive creation and numeric suffixes prevent collisions, including another process saving in the same second. PNG encoding completes before the clipboard is cleared.

After a successful save, the model releases the captured pointer and opens the file explicitly with Preview through `NSWorkspace`. A Preview launch failure preserves the save and reveals the file in Finder. Copy Screenshot remains a clipboard-only action.

## Application boundary and updates

Diorama retains its existing unsandboxed boundary for global input, Accessibility, and private display APIs. Both user permissions are required before display creation and checked once a second. Revocation releases the pointer, stops capture, and removes the display. See [security and privacy](security.md).

`AppUpdater` owns Sparkle's standard updater controller. It starts only when `DioramaUpdatesEnabled` is true in the packaged app; local builds leave it off. The app menu and Settings observe Sparkle's availability and preferences. Installation uses normal application termination, so the model's shutdown releases input and destroys the display before relaunch.

The Swift package pins Sparkle. Packaging embeds its framework and installer tools, removes unused XPC services, strips development library search paths, signs inside-out, and verifies the resulting bundle. `VERSION` supplies both bundle version fields. See [releases](releases.md) for signing, notarization, signed feeds, and publication, and [development](development.md) for tests and live interaction checks.

[Documentation](README.md)
