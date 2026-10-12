<p align="center">
  <img src="Resources/MamoriIcon.png" alt="Mamori" width="72">
</p>

<h1 align="center">Mamori · 守 · お守り</h1>

<p align="center">Let your Mac stay awake. Let yourself step away.</p>

<p align="center">
  English · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a>
</p>

A small menu-bar companion for AI sessions, builds, and work that takes time.

Start a task, choose how long your Mac should stay awake, and get on with your day. Mamori puts a few useful controls in one quiet place, with a familiar Mac interface and an end to every session that you control.

**[Download the published preview](https://github.com/fayerhill/mamori/releases/tag/v0.1.0-preview)** · [Build the current app](Documentation/Signing.md) · [Progress](Documentation/Progress.md)

Apple silicon · macOS 14+ · English, 简体中文, 日本語

> **Current source: 0.2.0.** A properly Apple-signed local build includes real helper setup, network guarding, optional app quitting, and complete uninstall. These paths still need controlled live validation. The published **v0.1.0-preview** downloads are older ad-hoc builds: keep-awake and observation work there, while guard and app-quit effects remain simulations. Developer ID signing and notarization are required before general signed distribution.

<p align="center">
  <img src="Artifacts/home-en.png" alt="Mamori's compact native Mac panel with keep-awake and guarding controls in safe preview mode" width="280">
</p>

## For the work between “start” and “done”

An AI session needs another hour. A build is still running. A research task has more to do while you take a break. Keeping the Mac awake should take one decision, instead of another thing to keep checking.

Mamori helps with that small, practical part of the job. Set a duration, or keep your Mac awake while Mamori runs. Your display can still sleep, and your screen can still lock.

## A little utility, with a clear point of view

**Be present without demanding attention.** Mamori lives in the menu bar. Its compact panel uses familiar macOS controls, system typography, and your light or dark appearance. You open it when you need it.

**Make every action a choice.** Keep-awake starts off. You choose the duration and the applications that matter to you. A timer ends on its own; quitting Mamori releases keep-awake. Closing the panel simply puts it away.

**Leave the Mac feeling like your Mac.** Keep-awake uses a temporary assertion rather than rewriting power preferences. Mamori does not edit shell profiles, PATH, DNS, proxy settings, or GlobalProtect configuration. There is no telemetry or automatic launch at login.

The name brings together **Mamori, 守, and お守り**. It reflects the idea behind the project: a small companion you keep close, with clear controls and a modest footprint.

## What you can do

| Feature | Why it matters | Available today |
| --- | --- | --- |
| **Keep Mac Awake** | Choose a duration or keep the Mac awake while Mamori runs. Useful when a local task needs more time. | Works in the normal app. |
| **A clear stopping point** | Turn keep-awake off, let the timer finish, or use Restore & Quit. Display sleep and screen locking remain available. | Works in the normal app. |
| **VPN connection awareness** | Check what Mamori can observe about GlobalProtect from the same small panel. | Read-only observation; it does not enforce network protection. |
| **Choose the apps that matter** | Search installed apps and optionally quit the running selections after a confirmed VPN loss. | Requires an explicitly enabled, signed guard session; uncertain evidence does not trigger quitting. |
| **An explicit guard session** | Set up the helper, discover the connected tunnel and gateway, then start guarding. | Implemented for a narrow GlobalProtect configuration in signed local builds; live validation remains pending. |
| **Complete Uninstall** | Restore owned network resources and unregister the service before removing this app and its user data. | Available in Settings with confirmation; preview simulates it. |

Keep-awake prevents idle system sleep. It does not override closing the lid or choosing Sleep, and it cannot guarantee that an AI service or remote job keeps running.

## Try it in a minute

1. **[Download the DMG](https://github.com/fayerhill/mamori/releases/download/v0.1.0-preview/Mamori-macOS-arm64.dmg)** and drag the app you want into Applications.
2. Open **Mamori** for real keep-awake controls, or **Mamori Preview** to explore the full interface safely.
3. Choose **Always** or a custom duration. Use **Restore & Quit** when you're finished.

These links are for the older **v0.1.0-preview** release, not the current 0.2.0 local developer build. No Xcode, Homebrew, or Terminal setup is required for those downloads. Prefer a ZIP? The [release page](https://github.com/fayerhill/mamori/releases/tag/v0.1.0-preview) includes separate normal and preview apps, Quick Start guides, and checksums.

**This release is an ad-hoc signed, non-notarized development build.** macOS may block first launch; see the [download guide](Documentation/Download.md). Preview reads the installed-app catalog, but its VPN, power, firewall, and quit effects are simulated. It will not disconnect your VPN or close your work apps.

## Where Mamori is heading

The current source implements a small, explicit response to a lost VPN connection: keep the default-deny policy in place and, if you choose, quit selected apps after confirmed loss. The helper provides the authoritative status; unreadable VPN evidence does not silently become a confirmed disconnection. A signed local build can set up that helper after explicit macOS approval.

Settings also offers **Complete Uninstall**. After confirmation, it releases keep-awake, verifies network restoration, unregisters the helper, and permanently removes this running app bundle and this user's owned settings, caches, support files, and saved state. It does not use Trash or remove source code, other app copies, other users' data, or OS logs. A failure stays visible instead of claiming cleanup succeeded.

The next step is controlled live validation and a Developer ID signed, notarized public distribution. Universal VPN support and automatic reconnection are outside this MVP. Follow the [progress and roadmap](Documentation/Progress.md), or read the [network design and its limits](Documentation/NetworkGuard.md). A detected VPN or a valid signature is not proof of network enforcement.

<details>
<summary><strong>Build it, inspect it, or contribute</strong></summary>

The app uses SwiftUI, AppKit, and Swift Package Manager, with no remote package dependencies. Building requires Xcode with Swift 6 on macOS 14 or later.

```sh
git clone https://github.com/fayerhill/mamori.git
cd mamori
./Scripts/build.sh
./Scripts/preview.sh
```

Build signing defaults to `auto`: Developer ID, then Apple Development, then ad-hoc. Use `SIGNING_MODE=dev` for a functional local helper build or `SIGNING_MODE=adhoc` for the limited preview. See [signing and distribution](Documentation/Signing.md). Run isolated tests with `./Scripts/test.sh`; capture simulations with `./Scripts/preview.sh --capture /private/tmp/mamori-preview`. The public packager rejects Apple Development builds.

| Module | Responsibility |
| --- | --- |
| `Sources/Mamori` | Interface, localization, and coordination. |
| `Sources/MamoriCore` | Pure session state, VPN evidence, and guard policy. |
| `Sources/MamoriSystem` | Native power, application, VPN, and XPC adapters. |
| `Sources/MamoriGuard` | Experimental privileged network service and restoration. |

Have an idea or something feels wrong? [Open an issue](https://github.com/fayerhill/mamori/issues) with your macOS version and what you expected. Keep private VPN addresses and credentials out of public reports.

</details>

[Download guide](Documentation/Download.md) · [Signing](Documentation/Signing.md) · [Installation & removal](Documentation/Installation.md) · [Behavior](Documentation/Behavior.md) · [Progress](Documentation/Progress.md)
