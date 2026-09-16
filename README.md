<div align="center">

<img src="Support/AppIcon.png" alt="Diorama" width="88">

# Diorama

**A virtual display for taking clean screenshots on macOS.**

<p>
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-%E2%89%A515-0a0a0a?style=flat-square&logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-0a0a0a?style=flat-square&logo=swift&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple-Silicon-0a0a0a?style=flat-square">
  <img alt="Retina screenshots" src="https://img.shields.io/badge/screenshots-Retina-0a0a0a?style=flat-square">
</p>

[Download](#download) · [Documentation](docs/README.md) · [Development](docs/development.md) · [Security](docs/security.md)

</div>

<p align="center">
  <img width="100%" alt="A Mac desktop running inside Diorama" src="https://github.com/user-attachments/assets/4980e638-3788-4a44-bed9-79213b4f4937" />
</p>

Capture clean Retina screenshots of your apps without tidying or rearranging your
desktop. Diorama gives you a separate Mac desktop inside one window. Arrange your
apps, work with them directly, and capture the scene when it's ready.

## Download

**[Download Diorama](https://github.com/pdparchitect/diorama/releases/latest)** for macOS 15 or later on Apple Silicon.

Download `Diorama-arm64.zip`, unzip it, and move Diorama to **Applications**.

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
- [All documentation](docs/README.md)
- [Changelog](CHANGELOG.md)
