# Local build and safe preview

Mamori is a native macOS app for macOS 14 or later. Building requires Xcode with its command-line tools. The current package has no third-party dependencies and does not need Homebrew, a package installer, or changes to shell startup files.

Run the existing scripts from the project directory:

```sh
./Scripts/build.sh
./Scripts/preview.sh
```

The build stays in this project: Swift build products are in `.build`, and the assembled application is `build/Mamori.app`. Nothing is copied to `/Applications` or installed globally by either script. The default build uses an ad-hoc signature and does not provide an installable privileged network guard.

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

Network protection additionally requires a suitable Developer ID signed application and bundled helper, explicit service setup, and the macOS approval flow. An ad-hoc local build reports that this capability is unavailable. Building or previewing does not register that helper. A Developer ID signing identity can be provided to the existing build script through its `SIGNING_IDENTITY` environment variable without changing global configuration.

The app does not automatically reconnect a VPN or reopen terminated applications. Choose Apps includes installed applications from `/Applications`, `/System/Applications`, and your user `Applications` folder, including Utilities and other ordinary subfolders. It also includes eligible currently running applications outside those folders. Applications do not need to be running to be selected. Directory discovery is cached briefly; Refresh rescans it. Hidden folders, nested application helpers, and deeply nested package contents are not scanned.

Mamori itself, recognized VPN clients and their control components, background-only executables, and critical system applications are excluded so automatic quitting cannot stop its own protection or the VPN recovery controls. Other installed GUI applications, including Terminal and iTerm, can be selected explicitly. Selecting a browser or terminal app covers the whole application and all its windows or sessions. The optional force-quit setting can discard unsaved work. Node, Python, and unrelated background processes are never selected implicitly. Before acting, Mamori resolves a selected application to a fresh running instance and checks its process identity; a stopped application is not launched merely to quit it.

## Restore and remove

For a preview-only run, use **Restore & Quit Mamori**, then delete the local app bundle, build products, and any screenshot output you no longer want. Retain the source directory if you intend to rebuild. No background helper was installed by preview.

If real network protection was configured:

1. Keep the original signed app and helper available.
2. Stop protection and wait for a confirmed inactive/restored status.
3. Use **Remove background service**. This operation must restore Mamori-owned network resources successfully before unregistering the helper.
4. Use **Restore & Quit Mamori**, then remove your local app and build outputs.

Do not remove the app or unregister the helper while restoration is incomplete. A crash or forced termination may leave the guard intentionally in place. Reopen the same signed app and complete restoration first. Do not manually delete the recovery journal to silence an error: it records the resources needed for recovery.

The privileged helper owns only its Mamori recovery data under `/Library/Application Support/Mamori` and its own firewall resources. Let the helper perform that cleanup. Never flush the entire system firewall or remove another application's rules as an uninstall shortcut.

If real-mode preferences were used, the app's own preference domain is `com.mamori.app`. Removing that domain after a clean shutdown resets Mamori's language and application selections. Do not clear unrelated preferences. macOS-owned unified logs, launch records, and shell history are not Mamori cleanup targets and should not be deleted.
