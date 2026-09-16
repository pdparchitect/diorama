# Security and privacy

Diorama runs outside App Sandbox. Its existing design requires a session-wide event tap, Accessibility control of other applications' windows, and private CoreGraphics virtual-display interfaces. Releases use hardened runtime with no entitlement grants. Diorama is a view of the current login session, not an isolated computer or security boundary.

Screen Recording provides the stage picture and screenshots. Accessibility provides pointer control, hotkeys, and window movement. The event tap rewrites pointer locations, suppresses primary wallpaper gestures inside the stage, and consumes Diorama's five shortcuts. It does not log or forward keystrokes. Diorama does not capture audio. Screenshots stay on your Mac.

## Updates and network access

Distributed releases use [Sparkle](https://sparkle-project.org/) to check the public [GitHub release feed](https://github.com/pdparchitect/diorama/releases/latest/download/appcast.xml). Checks contact GitHub and its asset delivery services; Diorama disables Sparkle system-profile reporting. There is no GitHub token in the app. Automatic checks and automatic installation are separate settings.

The feed and ZIP are signed with the publisher's Ed25519 key. The app requires signed feeds and verifies the archive before extraction. Each release ZIP contains a Developer ID signed app, notarized by Apple with its ticket stapled. Feed archive links use immutable release tags.

Sparkle's framework, `Autoupdate`, and `Updater.app` are embedded and signed with the same team as Diorama. They replace and relaunch the app. Neither Sparkle XPC service is needed or shipped. This preserves Diorama's existing unsandboxed boundary without adding entitlement exceptions. The build copies Sparkle's license into the app.

## Compatibility

`CGVirtualDisplay` is not public SDK API and may change with macOS updates. Notarization and signature validation do not guarantee compatibility with future macOS releases. See [architecture](architecture.md) for the ABI assumptions and [development checks](development.md#check-changes) for live validation.

[Documentation](README.md)
