# Using Diorama

## Setup

Move Diorama to Applications before opening it. The setup screen's **Allow…** buttons open the corresponding macOS settings:

- **Screen & System Audio Recording** lets Diorama capture the virtual display. Relaunch after granting it; Diorama does not record audio.
- **Accessibility** lets Diorama fence the pointer, route input into the stage, and move other applications' windows.

Both permissions are required before the display starts. Revoking either stops capture, releases the pointer, and removes the display. If Settings shows an obsolete grant as allowed, quit Diorama, remove that entry, add the current application, and reopen it. Changing from an ad-hoc or Apple Development build to a Developer ID release may require granting permissions again. Keep the app in the same location.

## Work inside the stage

The stage is a real virtual display in your current macOS login session, with its own wallpaper, menu bar, Spaces, and resolution. The pointer is fenced off its desktop edge on your physical screens. Move into the stage's picture to interact: clicks, dragging, scrolling, and typing go to its windows. Move out, push against the picture's edge, or choose **Stage → Release Pointer** to return.

Use **Stage → Interactive** to switch to a view-only stage. A plain left-click on empty wallpaper is ignored so macOS's **Click wallpaper to reveal desktop** action does not sweep windows away across all displays. App windows, menus, the Dock, and desktop context clicks remain interactive. Diorama does not change your global desktop settings.

The toolbar and Stage menu target the last active application when Diorama is frontmost. Closing the stage quits the app and removes the virtual display; macOS moves its windows to a remaining display. Capture failures release the pointer and offer **Try Again**. Diorama also retries after five seconds.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌃⌥⌘D | Send the front window to Diorama |
| ⌃⌥⌘B | Bring the front window back |
| ⌃⌥⌘R | Return all windows |
| ⌃⌥⌘I | Toggle interaction |
| ⌃⌥⌘S | Save a screenshot and open Preview |
| ⇧⌘C | Copy a screenshot while Diorama is active |

The five Control-Option-Command shortcuts work globally while Diorama has Accessibility access.

## Screenshots and resolution

The camera button saves a full-resolution PNG of the virtual desktop, including its wallpaper, menu bar, and windows, without the cursor. Files go to `~/Pictures/Diorama` and open in Preview for copying, cropping, or annotation. Repeated captures get numeric suffixes so existing images are preserved. If Preview cannot open, Finder reveals the saved image. **Stage → Copy Screenshot** captures directly to the clipboard.

**Stage → Resolution** offers Retina sizes from 1024 × 576 to 1920 × 1080 points, backed by 2048 × 1152 to 3840 × 2160 pixels. The default is 1920 × 1080 points. macOS's screen-sharing indicator is system UI; full-desktop captures retain the menu bar.

## Updates

In a distributed release, use **Diorama → Check for Updates…** or Settings. Daily checks are enabled by default; automatic download and installation are a separate opt-in. Development builds disable the updater.

**Install and Relaunch** restarts Diorama, which removes and then recreates its virtual display. Windows on the stage return to a remaining display during shutdown; arrange them again after relaunching.

[Documentation](README.md)
