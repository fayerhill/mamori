# Mamori

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md)

**Mamori · 守 · お守り** is a small native macOS menu-bar utility for focused work: keep your Mac awake, choose apps to quit on a confirmed VPN drop, and explore a deliberately limited network-guard prototype.

The compact interface uses system sans-serif typography, standard macOS controls, and the system's light or dark appearance. Start guarding uses the system accent color; Stop guarding is red. There are no decorative hero graphics or oversized headings.

**Current build:** local MVP, macOS 14 or later. The default ad-hoc build supports keep-awake and a fully isolated interactive preview. Real network protection requires a Developer ID signed app and background service. No firewall protection is claimed by the local unsigned/ad-hoc preview.

<img src="Artifacts/home-en.png" alt="Mamori safe preview in English with system sans-serif typography" width="280">

See [development progress and next steps](Documentation/Progress.md) for completed work, validation evidence, and remaining release requirements.

## Download

Get the [v0.1.0 development preview](https://github.com/fayerhill/mamori/releases/tag/v0.1.0-preview) for **Apple silicon Macs running macOS 14 or later**. No Xcode, Homebrew, or Terminal setup is needed to run the app downloads.

- **Mamori-macOS-arm64.zip**: the normal menu-bar app, with real keep-awake and read-only GlobalProtect observation.
- **Mamori-Preview-macOS-arm64.zip**: the safe interactive preview. Its VPN, power, firewall, and app-quit actions are simulated.
- **Mamori-macOS-arm64.dmg**: both apps with an Applications shortcut for drag-and-drop installation.
- **SHA256SUMS**: checksums for these downloads. Each package includes a Quick Start guide.

These are ad-hoc signed, non-notarized **development builds**. The normal download cannot activate privileged network protection; automatic app quitting also requires an armed guard and is therefore only demonstrated in the safe preview. A Developer ID signed helper and controlled integration testing are still required. See [download and first-launch instructions](Documentation/Download.md).

## Run

Clone the repository, then build and open the safe preview:

```sh
git clone https://github.com/fayerhill/mamori.git
cd mamori
./Scripts/build.sh
./Scripts/preview.sh
```

After building, open `build/Mamori.app` for normal operation or `build/Mamori Preview.app` for safe simulation. Built apps are local outputs and are not committed to this repository.

The preview has its own clearly marked window and bundle identifier. It reads the installed-app catalog, but uses simulated VPN, power, firewall, and application-termination actions. It does not change the current VPN, firewall, power assertions, or real applications. The preview bundle always selects this mode, even when opened directly in Finder.

## Included

- A compact 280 × 290 pt panel and a menu-bar status item, with an understated frosted-glass-style shield icon.
- English by default, with Simplified Chinese and Japanese in Settings.
- Keep Mac Awake: Always while Mamori runs, or a custom duration of 1–10,080 minutes. Display sleep and screen lock remain available. The assertion ends when the timer expires, the option is disabled, or Mamori quits.
- A searchable installed-app picker, including apps that are not currently running. Standard application directories are scanned and cached for 30 seconds. Only selected apps running at the moment of a confirmed drop are affected. Auto-quit is off by default. Optional force quit has a five-second grace period and checks process identity again before acting.
- A conservative read-only GlobalProtect observer. A generic `utun` interface alone is never treated as a verified VPN.
- A privileged background-service implementation with a narrow signed XPC interface, a private recovery journal, explicit restoration acknowledgment, and a deliberately limited PF prototype.
- A simulation of VPN loss and recovery, with no real network or application actions. Recovery never reconnects the VPN or relaunches applications.
- Restore & Quit cancels queued auto-quit actions, releases keep-awake, and waits for network restoration before exiting. A restoration error keeps a visible retry action available.

Keep-awake is independent of network guarding. Stopping the guard does not cancel an independently enabled keep-awake timer; quitting Mamori cancels both. Closing the popover or preview window does not quit the menu-bar application.

## Network protection boundaries

The first implementation supports a narrow GlobalProtect configuration, not every VPN. It needs confirmed literal IPv4 gateway addresses, a specific active full-tunnel interface, and the stock Apple PF filter anchor with no competing firewall or existing state table. Route checks sample two external IPv4 addresses; they do not prove full-tunnel coverage. Full-tunnel operation remains an explicit deployment assumption. It refuses unsupported configurations instead of changing other applications' firewall rules or flushing their connections. IPv6 direct traffic is blocked by the default deny rule; this version does not support IPv6 VPN gateway transport.

Approved gateway traffic and minimal DHCP are exceptions to the direct-traffic block. PF cannot distinguish all applications sharing an allowed gateway IP. This is a local prototype; PF is not a supported Apple product API. See [NetworkGuard.md](Documentation/NetworkGuard.md) for the exact assumptions and limitations.

There is no auto-reconnect, no launch-at-login behavior, no telemetry, no third-party package dependency, and no shell profile, PATH, DNS, proxy, or GlobalProtect configuration change.

## Build and verification

Requires Xcode with Swift 6. The project uses Swift Package Manager and has no remote dependencies.

```sh
./Scripts/build.sh
./Scripts/test.sh
./Scripts/preview.sh --capture /private/tmp/mamori-preview
```

All automated tests exercise pure state and policy code. They do not load PF rules, register a daemon, create power assertions, terminate real applications, or disconnect a VPN. Native UI capture runs only in demo mode: the preview bundle enables it automatically, while the normal app requires `--demo` with `--capture`. Use `/private/tmp` for captures to avoid protected Documents-folder permissions.

To produce a properly signed build after configuring an Apple Developer identity:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./Scripts/build.sh
```

This only builds and signs. Installation, administrator approval, real firewall activation, notarization, and leak testing are separate steps. None were performed while developing this local preview.

## Files

- `Sources/Mamori`: native interface, localizations, and effect orchestration.
- `Sources/MamoriCore`: pure session reducer, VPN evidence classifier, and guard policy.
- `Sources/MamoriSystem`: native power, application, VPN, and XPC adapters.
- `Sources/MamoriGuard`: privileged background service.
- `Tests/MamoriCoreTests`: deterministic lifecycle and policy tests.
- `Artifacts`: actual native preview screenshots.
- `Documentation`: behavior, installation, cleanup, and network limitations.

To package downloads from a completed build, run `./Scripts/release.sh --dmg`. It verifies the clean app archives and generates distribution assets and checksums in `build/release`; it does not install or launch them.

See [Installation.md](Documentation/Installation.md) for removal. Normal Quit restores active behavior but keeps the app and preferences. Complete removal must restore the service first; it does not erase unrelated terminal history, system logs, authorization records, or backups.
