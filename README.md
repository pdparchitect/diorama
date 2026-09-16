# Diorama

A desktop in a box.

[Download](https://github.com/pdparchitect/diorama/releases) · [Documentation](docs/README.md) · [Development](docs/development.md)

Keep a complete Mac desktop inside one window. Arrange apps on its virtual display, work with them directly, and capture clean Retina screenshots without rearranging your own desktop.

<p align="center"><img src="Support/AppIcon.png" width="200" alt="Diorama application icon"></p>

## Download

Requires macOS 15 or later on Apple Silicon. Download `Diorama-arm64.zip` from [Releases](https://github.com/pdparchitect/diorama/releases), unzip it, and move Diorama to Applications.

Release builds support **Diorama → Check for Updates…**. Automatic checks and installation preferences are in Settings. To build from source, see [Development](docs/development.md).

## Get started

1. Open Diorama and allow Screen Recording and Accessibility when prompted. Relaunch after granting Screen Recording.
2. Press **⌃⌥⌘D** in another app to send its front window into Diorama.
3. Move the pointer into the picture to work. Move out to return to your desktop.
4. Use the camera button or **⌃⌥⌘S** to save a screenshot and open it in Preview.

Screenshots are saved in `~/Pictures/Diorama`. Closing the stage quits Diorama and returns its windows to a remaining display.

## Documentation

- [Using Diorama and keyboard shortcuts](docs/usage.md)
- [Permissions, privacy, and updates](docs/security.md)
- [Development and testing](docs/development.md)
- [Architecture](docs/architecture.md)
- [Downloads and updates](docs/releases.md)
- [Changelog](CHANGELOG.md)
