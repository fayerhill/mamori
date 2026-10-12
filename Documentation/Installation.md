# Local build and safe preview

Mamori is a native macOS app for macOS 14 or later. Building requires Xcode with its command-line tools. The current package has no third-party dependencies and does not need Homebrew, a package installer, or changes to shell startup files.

Run the existing scripts from the project directory:

```sh
./Scripts/build.sh
./Scripts/preview.sh
```

The build stays in this project: Swift build products are in `.build`, and the assembled application is `build/Mamori.app`. Nothing is copied to `/Applications` or installed globally by either script. Signing defaults to `auto`: an accessible Developer ID Application identity, then Apple Development, then ad-hoc. A `dev` build embeds a usable local-development helper; an ad-hoc build cannot activate it. See [Signing.md](Signing.md) for explicit modes and public distribution requirements.

Install the normal app by extracting `build/Mamori.zip` into your Applications folder. The archive comes from clean staging; synced Documents folders may attach Finder metadata to loose `.app` copies that makes strict signature verification fail. `BUILD_OUTPUT_DIR` can select a non-synced output location for local verification.

The scripts can be invoked directly by a development tool using a non-interactive subprocess. You do not need to paste commands into an interactive shell, change shell history settings, edit a shell profile, or install shell integrations. If you choose to type commands in Terminal, Terminal and your shell may keep their ordinary history; Mamori does not read or erase it.

## Preview without touching the VPN

`Scripts/preview.sh` opens `build/Mamori Preview.app`, which always selects demo mode. It reads the installed-app catalog so you can select actual apps, but all connection changes, power assertions, firewall operations, and quit actions are simulated. The real termination adapter is not connected. The preview does not disconnect or reconnect any VPN, change firewall rules, register a helper, acquire a power assertion, or quit another application.

Use the preview's simulated connection controls to inspect the connected and blocked states. Capture its 280 × 290 pt panel states in a temporary directory:

```sh
./Scripts/preview.sh --capture /private/tmp/mamori-preview
```

That command writes preview images into the chosen directory. `/private/tmp` avoids protected Documents-folder permissions that can prevent capture. The normal app rejects `--capture` without `--demo` before the model is created; the preview bundle is always in demo mode, including when opened directly without arguments. Normal macOS app-launch bookkeeping, caches, and system logs may still exist; demo mode is not a promise of leaving no operating-system records.

The isolated tests use synthetic events and do not activate real platform services:

```sh
./Scripts/test.sh
```

These tests check orchestration and policy logic. They are not proof that a live VPN or firewall blocks every packet. Do not disconnect the real VPN as part of preview or unit-test verification.

## Real-mode prerequisites

Opening `build/Mamori.app` without `--demo` uses real, read-only connection observation. Keep-awake remains off until you turn it on. It uses a temporary process-owned assertion, not a persistent power preference. Always means while Mamori runs; a custom duration ends automatically. Normal Quit also releases it. The screen may sleep or lock; lid closure, explicit sleep, shutdown, and low battery are outside this guarantee.

Network protection requires an Apple-signed application and embedded helper with matching Team IDs, explicit service setup, and macOS approval. Apple Development signing enables local development; Developer ID signing and notarization are the public distribution path. Ad-hoc builds cannot enable the guard. Building or previewing never registers the helper. After setup, the app can ask the helper to discover the current gateway and tunnel without changing network settings; inspect the result before starting protection. A valid signature or successful discovery does not establish real packet enforcement.

The app does not automatically reconnect a VPN or reopen terminated applications. Choose Apps includes installed applications from `/Applications`, `/System/Applications`, and your user `Applications` folder, including Utilities and other ordinary subfolders. It also includes eligible currently running applications outside those folders. Applications do not need to be running to be selected. Directory discovery is cached briefly; Refresh rescans it. Hidden folders, nested application helpers, and deeply nested package contents are not scanned.

Mamori itself, recognized VPN clients and their control components, background-only executables, and critical system applications are excluded so automatic quitting cannot stop its own protection or the VPN recovery controls. Other installed GUI applications, including Terminal and iTerm, can be selected explicitly. Selecting a browser or terminal app covers the whole application and all its windows or sessions. The optional force-quit setting can discard unsaved work. Node, Python, and unrelated background processes are never selected implicitly. Before acting, Mamori resolves a selected application to a fresh running instance and checks its process identity; a stopped application is not launched merely to quit it.

## Restore, quit, or completely uninstall

**Restore & Quit** ends active behavior but leaves the app and preferences for another session. It cancels pending automatic app actions, releases keep-awake, and waits for network restoration. A failure remains visible with a retry path.

**Settings → Complete Uninstall** is a separate confirmed action in the current source. It performs this sequence:

1. Stop accepting new work and cancel queued application actions.
2. Release keep-awake and require the helper's network-restoration acknowledgment.
3. Unregister Mamori's background service and its own automatic-start registration, if present.
4. Remove this user's exact Mamori preferences, caches, Application Support, and Saved Application State paths.
5. Permanently remove the validated running production app bundle and exit.

The app is deleted directly, **not moved to Trash**. It does not remove another installed copy, the separate Preview app, downloaded archives, source code, another user's data, shared libraries, or system-managed logs and authorization records. The fixed user-data namespace is `com.mamori.app`; no arbitrary privileged file-deletion interface is exposed. Preview simulates uninstall and deletes nothing.

Read-only, translocated, or protected installs can prevent self-removal. The app reports incomplete cleanup and remaining paths rather than claiming success or bypassing permissions. Keep the recovery-capable app available until service restoration and unregistration succeed. Do not manually delete a recovery journal to suppress an error.

For a signed guard, helper-owned recovery data is confined to `/Library/Application Support/Mamori` and its own PF resources. Let the helper remove those resources. Never flush the entire firewall, delete another application's rules, clear shell history, or erase system logs as an uninstall shortcut.

See [Signing.md](Signing.md) for build types and [Download.md](Download.md) for the older published preview. Complete uninstall and actual network behavior still require controlled integration validation; the development checks do not disconnect a real VPN.
