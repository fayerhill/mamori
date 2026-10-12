# Build signing and distribution

Mamori separates a functional local development build from a public distribution build. Neither signing nor notarization proves VPN protection. Installing or starting the network guard is always a separate, explicit action in Mamori and macOS Settings.

## Choose a signing mode

`Scripts/build.sh` accepts `SIGNING_MODE`:

| Mode | Identity | Intended use |
| --- | --- | --- |
| `auto` (default) | Prefer accessible Developer ID Application, then Apple Development; otherwise ad-hoc | Convenient local builds; the script reports the actual mode |
| `dev` | Apple Development or Mac Developer | Local development with the real embedded helper; not a public download |
| `developerID` | Developer ID Application | Distribution preparation; notarization and controlled integration validation are still required |
| `adhoc` | No certificate | Limited normal app plus safe preview; the real helper is unavailable |

Explicit `dev` or `developerID` mode fails if no suitable identity is accessible. It does not silently produce an ad-hoc substitute. `SIGNING_IDENTITY` can select a specific keychain identity by certificate name or fingerprint; optional `SIGNING_TEAM_ID` requires an exact expected Team ID. No private key or account password belongs in the repository or a shell command.

Build a functional local development app using an existing Apple Development identity:

```sh
SIGNING_MODE=dev CONFIGURATION=release ./Scripts/build.sh
./Scripts/validate-bundles.sh
```

The generated `build/Mamori.zip` contains the real app and helper. Extract it into Applications before explicitly setting up its background service. The app and service require the same Apple signing Team ID. A locally signed build is not a notarized general-public download; another Mac may not accept a development certificate. `Scripts/release.sh` refuses to package this mode for public distribution.

To deliberately build the limited downloadable preview instead:

```sh
SIGNING_MODE=adhoc CONFIGURATION=release ./Scripts/build.sh
./Scripts/release.sh --dmg
```

Each build replaces only its generated app copies and clean archives in `build`. Preserve a needed previous build before selecting another mode. The separate `Mamori Preview.app` always uses simulated effects and contains no privileged helper, regardless of its signing mode.

Set `BUILD_OUTPUT_DIR` to keep a separate local build, for example `SIGNING_MODE=adhoc BUILD_OUTPUT_DIR="$PWD/work/ui-preview" ./Scripts/build.sh`. The release packager continues to consume the default `build` directory. Do not build concurrently into the same Swift scratch directory or output directory.

Synced folders such as Documents can add Finder metadata to assembled `.app` directory copies and invalidate strict signature checks. The ZIPs are created from clean staging before this happens; use those archives for installation outside the synced folder. For a directly verifiable local output directory, set `BUILD_OUTPUT_DIR=/private/tmp/mamori-final-build`.

## Signature and bundle checks

The build signs the nested helper first, then the app, then the separate preview. All executables use Hardened Runtime. Developer ID signatures require Apple's secure timestamp; local development and ad-hoc signatures do not request one. No broad entitlement exception or restricted service-management entitlement is added.

The shared validator checks:

- Fixed identities `com.mamori.app`, `com.mamori.guard`, and `com.mamori.preview`.
- Valid signatures, matching signing mode and Team ID, architecture, and app versions.
- The helper's exact bundle-relative executable path and sole Mach service.
- No automatic-start keys in the demand-started daemon plist, and no helper in the preview.

Validation reads files and code signatures only. It never registers a service, launches an app, changes PF, or disconnects a VPN. Runtime XPC authentication and helper approval remain separate checks.

`./Scripts/test-bundles.sh` checks six synthetic bundle cases, including tampered code, unexpected daemon startup, wrong helper identity, and a helper accidentally included in the preview. Its inert fixture executables are never launched.

## Developer ID and notarization

A Developer ID Application certificate and its private key must be available in the signing keychain. Apple Development is not a substitute for public notarization.

```sh
SIGNING_MODE=developerID CONFIGURATION=release ./Scripts/build.sh
./Scripts/release.sh --dmg --notarize mamori-distribution
```

`mamori-distribution` is the name of an existing `notarytool` keychain profile. Configure that profile using Apple's documented credential workflow; do not put account secrets in scripts or environment files. Passing `--notarize` explicitly authorizes uploading the assembled software to Apple's notary service. Without that option, packaging does not contact the notary service and labels the result unnotarized.

The notarization path submits both apps, requires an `Accepted` response, staples and validates their tickets, and checks their Gatekeeper assessments before packaging. If a DMG is requested, the script signs it with the Developer ID identity, notarizes it, and staples its ticket too. Notary responses stay under `build/notarization`. Failures stop the run before updating release assets. If multiple certificates share a name, pass `SIGNING_IDENTITY` explicitly for DMG signing.

The final `build/release` directory contains app ZIPs, the optional DMG, `RELEASE-INFO.txt`, and `SHA256SUMS`. Upload only the files listed in the current checksum manifest plus that manifest. The release information records signing and notarization status. Old output files are not automatically treated as part of a new release.

Signed or notarized output still needs controlled validation of service approval, restoration, complete uninstall, VPN compatibility, and actual packet behavior. See [NetworkGuard.md](NetworkGuard.md) and [Progress.md](Progress.md).

## Apple references

- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Getting Started with SMAppService](https://developer.apple.com/forums/thread/802443)
