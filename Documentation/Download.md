# Download and open Mamori

Use the app assets attached to a GitHub release. GitHub's **Source code** archives contain the project for developers, not an installed app.

| Download | Purpose |
| --- | --- |
| `Mamori-macOS-arm64.zip` | Normal app: keep-awake and read-only GlobalProtect observation. |
| `Mamori-Preview-macOS-arm64.zip` | Safe interactive preview with simulated effects. |
| `Mamori-macOS-arm64.dmg`, when provided | Both apps and an Applications shortcut for drag-and-drop installation. |
| `SHA256SUMS` | Checksums for the accompanying app downloads. |

These initial downloads require an Apple silicon Mac and macOS 14 or later. They are ad-hoc signed development builds, not notarized releases. The normal app cannot install or activate its privileged network guard in this build. Automatic app quitting requires an armed guard and is therefore only demonstrated in the safe preview. Keep-awake works independently; a detected VPN is not proof of Mamori firewall protection.

## Install without Terminal

1. Download the ZIP for the app you want, then double-click it. Open the extracted folder.
2. Drag the app into **Applications**. For a DMG, open it and drag the app onto its **Applications** shortcut, then eject the disk image.
3. Open the app from **Applications**. Click its shield icon in the menu bar to show the panel.

No Xcode, Homebrew, or command-line setup is needed to run these downloads. Preview always simulates VPN, firewall, keep-awake, and app-termination effects. Its app picker reads the installed-app catalog without changing it.

If macOS blocks the development app, attempt to open it, then review **System Settings → Privacy & Security → Open Anyway** if you trust the source and the option is available. An organization-managed Mac may prevent an override. Follow [Apple's opening instructions](https://support.apple.com/102445); this project does not ask you to disable Gatekeeper or remove quarantine in Terminal.

Use **Restore & Quit** before removing Mamori. A preview-only run installs no background helper. If a separately signed guard was installed later, restore its network resources and remove that background service before deleting the app; see [Installation.md](Installation.md).

## Maintainer packaging

After building the final source, run:

```sh
./Scripts/release.sh
```

Use `./Scripts/release.sh --dmg` to add a disk image. The script consumes the existing clean `build/Mamori.zip` and `build/Mamori Preview.zip`, verifies their signatures and matching architectures, includes a Quick Start guide, and writes assets plus `SHA256SUMS` into `build/release`. It does not rebuild, launch, install, publish, or notarize anything. The default build targets the host architecture; the packager derives the asset suffix from the actual binaries and rejects mismatched app/helper architectures.

Only upload files listed in the newly generated `SHA256SUMS`, together with that checksum file. Do not upload unfiltered build folders or stale assets. Current download instructions deliberately cover ad-hoc development builds; the script requires a guide update before accepting a future Developer ID distribution build.
