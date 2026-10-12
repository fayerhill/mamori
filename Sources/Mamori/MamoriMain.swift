import AppKit
import Foundation
import SwiftUI

@main
enum MamoriMain {
    static func main() {
        let arguments = ProcessInfo.processInfo.arguments
        let demo = arguments.contains("--demo") || Bundle.main.bundleIdentifier == "com.mamori.preview"
        if arguments.contains("--capture"), !demo {
            fputs("Screenshots require --demo; no real services were started.\n", stderr)
            exit(2)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(demo ? .regular : .accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var window: NSWindow?
    private var waitingToQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        model.onExit = { [weak self] in
            guard let self else { return }
            if waitingToQuit { NSApplication.shared.reply(toApplicationShouldTerminate: true) }
        }
        model.onStatusChange = { [weak self] in self?.updateStatusItem() }
        makeMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.setAccessibilityLabel("Mamori")
        updateStatusItem()
        let panel = NSPopover()
        panel.contentSize = NSSize(width: Theme.width, height: Theme.height)
        panel.behavior = .transient
        panel.animates = false
        panel.contentViewController = NSHostingController(rootView: MamoriView(model: model))
        popover = panel
        if model.isDemo { showPreviewWindow() }
        else { togglePopover() }

        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--capture"), arguments.indices.contains(index + 1) {
            let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            Task { await capturePreview(to: directory) }
        }
    }

    private func makeMainMenu() {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Mamori")
        applicationMenu.addItem(withTitle: "Show Mamori", action: #selector(showMamori), keyEquivalent: "0")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Hide Mamori", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Restore & Quit Mamori", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func showMamori() {
        if model.isDemo { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        else { togglePopover() }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusItem() {
        let image = NSImage(systemSymbolName: model.guardIsActive ? "checkmark.shield" : "shield", accessibilityDescription: "Mamori")
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = "Mamori · \(model.title)"
    }

    private func showPreviewWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Theme.width, height: Theme.height), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Mamori — Safe Preview"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Theme.background)
        window.contentView = NSHostingView(rootView: MamoriView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !waitingToQuit else { return .terminateLater }
        waitingToQuit = true
        Task { [weak self] in self?.model.beginQuit() }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func capturePreview(to directory: URL) async {
        guard model.isDemo else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for language in AppLanguage.allCases {
                model.resetDemo()
                model.language = language
                await settle()
                try capture(directory.appendingPathComponent("home-\(language.rawValue).png"))
            }
            model.language = .english
            model.screen = .awake
            model.awakeMode = .duration
            model.awakeMinutes = 90
            await settle()
            try capture(directory.appendingPathComponent("awake-duration.png"))
            model.screen = .applications
            if let app = model.apps.first { model.selectApp(app.id, selected: true) }
            model.setAutoQuit(true)
            await settle()
            try capture(directory.appendingPathComponent("application-picker.png"))
            model.screen = .home
            model.toggleGuard()
            await settle()
            try capture(directory.appendingPathComponent("protected-preview.png"))
            model.simulateVPN(false)
            await settle()
            try capture(directory.appendingPathComponent("blocked-preview.png"))
            model.screen = .settings
            await settle()
            try capture(directory.appendingPathComponent("settings.png"))
            model.resetDemo()
            model.language = .english
            await settle()
            print("Preview screenshots saved to \(directory.path)")
            fflush(stdout)
        } catch {
            print("Preview capture failed: \(error.localizedDescription)")
            fflush(stdout)
        }
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(500)) }

    private func capture(_ url: URL) throws {
        guard let view = window?.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CaptureError.unavailable
        }
        view.layoutSubtreeIfNeeded()
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CaptureError.unavailable }
        try data.write(to: url)
    }
}

private enum CaptureError: Error { case unavailable }
