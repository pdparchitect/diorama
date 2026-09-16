# Releases and updates

Diorama follows [Noodle's release process](https://github.com/pdparchitect/noodle/blob/main/docs/releases.md): versions and changelog notes select releases; CI tests, signs, notarizes, and verifies artifacts before creating a tag or publishing a download.

## One-time setup

The upstream repository must be public so downloads and the update feed work without credentials. GitHub Actions needs permission to create tags and releases. Add these encrypted Actions secrets to **pdparchitect/diorama** (or grant the repository access to organization secrets):

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64-encoded Developer ID Application certificate and private key archive |
| `MACOS_CERTIFICATE_PASSWORD` | Password for the P12 archive |
| `APP_STORE_CONNECT_API_KEY_P8` | App Store Connect API private key contents |
| `APP_STORE_CONNECT_KEY_ID` | API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | API issuer ID |
| `SPARKLE_PRIVATE_KEY` | Exported publisher Sparkle private key contents |

These are the same secret names as Noodle. Repository secrets do not transfer automatically between repositories. Import them from the secure originals; never commit private keys or print them in logs.

`Support/Info.plist` uses the same publisher public key as Noodle:

```text
1ZT5NrPiDPaQ54iHGSI1a9JIn6kTrmjQvzZRBA9f/sk=
```

Use its matching private key. Packaging fails if Sparkle cannot sign for the embedded public key. Back up the key securely. After shipping, do not casually replace it: requiring verification before extraction constrains [Sparkle key rotation](https://sparkle-project.org/documentation/#rotating-signing-keys), and ZIP updates cannot perform the Developer ID signed DMG recovery path. Keep the existing key available.

## Prepare a release

1. Set `VERSION` to an unused, higher `X.Y.Z`.
2. Move relevant Unreleased notes into `## [X.Y.Z] - YYYY-MM-DD` in `CHANGELOG.md`.
3. Run `make test` and review the changes.
4. Commit and push to `main`. **A new version with dated notes requests publication.**
5. Watch **Validate and release versions** finish. Download the public ZIP and test **Check for Updates…** from the preceding release.

Do not create tags manually or reuse versions. Unchanged versions skip publication. The initial `0.1.0` stays in development while the changelog contains only Unreleased notes; date that section when the credentials and first release are ready. PRs test and build without access to signing secrets or publishing. A manual run on `main` uses the same version rules.

## Pipeline

The workflow lints Actions syntax, validates versions and notes, runs Swift and release-automation tests, and verifies an ad-hoc development bundle. Documentation-only changes skip automatic app CI; changelog changes remain release inputs.

For a selected release, the Apple Silicon `macos-15` runner imports a temporary signing keychain, builds with Developer ID and secure timestamps, signs Sparkle inside-out, submits to Apple notarization, staples the ticket, and checks Gatekeeper. It signs and verifies the final ZIP and feed, then records hashes and the checked commit in `release.json`. Temporary signing material is removed even after failures.

Only then does a separate publication job create `vX.Y.Z` on the checked commit, upload the exact prepared files to a draft release, and publish it as latest:

- `Diorama-arm64.zip`
- `Diorama-arm64.zip.sha256`
- `appcast.xml`
- `release-notes.md`
- `release.json`

The fixed download name is [Diorama-arm64.zip](https://github.com/pdparchitect/diorama/releases/latest/download/Diorama-arm64.zip). The updater reads [appcast.xml](https://github.com/pdparchitect/diorama/releases/latest/download/appcast.xml), whose ZIP link names the immutable `vX.Y.Z` tag. Never replace published ZIPs or edit signed feeds. Keep earlier releases available.

Development CI artifacts are explicitly named `Diorama-development.zip`; they have no notarization and updates are disabled. They are not public releases.

## Recover a failed run

- **Tests or preparation failed:** fix the cause and rerun the failed jobs. No tag is created before preparation succeeds.
- **Upload or publication failed:** choose **Re-run failed jobs** on the original run. This downloads the saved prepared assets without rebuilding. The publisher resumes a draft only when every existing asset matches byte-for-byte and uploads only missing files. A completed identical release is also safe to retry.
- **Artifact mismatch, wrong tag, or a newer release exists:** inspect before proceeding. The publisher refuses to overwrite assets, move a tag, or roll back the update channel.

Prepared artifacts are retained for seven days. Do not rerun all jobs to recover an already tagged release: version planning treats that version as released. If artifacts have expired, recover the exact saved assets from secure storage or prepare a higher version; never rebuild an existing tag to replace its archive.

## Local packaging

For maintainers with the credentials already configured:

```sh
export DIORAMA_SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
export APPLE_API_KEY_PATH=/secure/path/AuthKey.p8
export APPLE_API_KEY_ID=YOUR_KEY_ID
export APPLE_API_ISSUER_ID=YOUR_ISSUER_ID
export SPARKLE_PRIVATE_KEY_PATH=/secure/path/sparkle.key
make release
```

This prepares verified files under `dist/release/` without tagging or publishing. It requires dated release notes and an Apple Silicon Mac. The final package enables daily update checks; automatic download/install remains opt-in. Installing an update restarts Diorama and removes its virtual display during shutdown.

[Documentation](README.md)
