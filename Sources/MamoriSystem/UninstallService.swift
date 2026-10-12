import Foundation
import Darwin
import ServiceManagement
import MamoriCore

/// A plan can only be created by validating the current Mamori bundle.
public struct UninstallPlan: Sendable {
    public let applicationURL: URL
    public let userDataURLs: [URL]
    public let preferenceDomain: String
    fileprivate let homeURL: URL
    fileprivate let identity: UninstallFileIdentity
}

public struct UninstallReport: Sendable {
    public let removedPaths: [String]
    public let applicationRemoved: Bool
}

public struct UninstallIssue: Sendable {
    public let path: String
    public let message: String
}

public struct UninstallFailure: LocalizedError, Sendable {
    public let issues: [UninstallIssue]
    public let removedPaths: [String]
    public var errorDescription: String? {
        issues.map { "\($0.path): \($0.message)" }.joined(separator: "\n")
    }
}

fileprivate struct UninstallFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

/// Internal dependencies let tests use isolated fixture bundles without touching services or preferences.
struct UninstallContext {
    let bundleURL: URL
    let executableURL: URL
    let bundleIdentifier: String
    let homeURL: URL
}

struct UninstallSafetyChecks {
    var verifyRestoredAndUnregistered: () throws -> Void
    var clearPreferences: () throws -> Void
}

/// No privileged deletion, shell command, or arbitrary caller-supplied path is accepted.
/// The caller must stop timers and preference writes, release keep-awake, and successfully
/// restore/unregister GuardClient before removal. Quit immediately after a successful result.
@MainActor public enum UninstallService {
    public static func prepare() throws -> UninstallPlan {
        guard let executable = Bundle.main.executableURL else {
            throw failure(Bundle.main.bundleURL, "The running application has no bundle executable.")
        }
        return try prepare(context: UninstallContext(
            bundleURL: Bundle.main.bundleURL,
            executableURL: executable,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            homeURL: FileManager.default.homeDirectoryForCurrentUser
        ))
    }

    public static func remove(_ plan: UninstallPlan) throws -> UninstallReport {
        try remove(plan, safety: UninstallSafetyChecks(
            verifyRestoredAndUnregistered: {
                guard !UserDefaults.standard.bool(forKey: "MamoriGuardMayOwnNetworkState") else {
                    throw failure(plan.applicationURL, "Network restoration is still pending. Restore the guard before uninstalling.")
                }
                for service in [SMAppService.daemon(plistName: GuardIdentity.plist), SMAppService.mainApp] {
                    switch service.status {
                    case .notRegistered, .notFound: break
                    default:
                        throw failure(plan.applicationURL, "A Mamori background service is still registered. Unregister it before removing the app.")
                    }
                }
            },
            clearPreferences: {
                UserDefaults.standard.removePersistentDomain(forName: GuardIdentity.app)
                guard UserDefaults.standard.synchronize() else {
                    throw failure(plan.homeURL.appendingPathComponent("Library/Preferences/\(GuardIdentity.app).plist"),
                                  "The preferences service did not confirm removal. The application was kept for retry.")
                }
            }
        ))
    }

    static func prepare(context: UninstallContext) throws -> UninstallPlan {
        let original = context.bundleURL.standardizedFileURL
        guard context.bundleIdentifier == GuardIdentity.app, original.pathExtension == "app" else {
            throw failure(original, "Only the running production Mamori app can uninstall itself. Preview and command-line builds cannot uninstall.")
        }
        guard let item = try metadata(original), item.kind == S_IFDIR else {
            throw failure(original, "The application must be an existing directory, not a symbolic link.")
        }
        let application = original.resolvingSymlinksInPath()
        let home = context.homeURL.standardizedFileURL.resolvingSymlinksInPath()
        guard !["/", "/Applications", "/System/Applications", home.path, home.appendingPathComponent("Applications").path].contains(application.path),
              !application.path.contains("/AppTranslocation/"),
              !application.path.hasPrefix("/Volumes/") else {
            throw failure(application, "Install Mamori in a writable Applications folder before using Complete Uninstall.")
        }
        let executable = application.appendingPathComponent("Contents/MacOS/Mamori")
        guard context.executableURL.standardizedFileURL.resolvingSymlinksInPath().path == executable.path,
              let executableItem = try metadata(executable), executableItem.kind == S_IFREG,
              let info = NSDictionary(contentsOf: application.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == GuardIdentity.app,
              info["CFBundleExecutable"] as? String == "Mamori",
              info["CFBundlePackageType"] as? String == "APPL" else {
            throw failure(application, "The running bundle does not match Mamori's expected application identity.")
        }
        let data = ownedDataURLs(home: home)
        guard !data.contains(where: { contains($0, application) || contains(application, $0) }) else {
            throw failure(application, "Move Mamori out of its own data directories before uninstalling.")
        }
        let plan = UninstallPlan(applicationURL: application, userDataURLs: data,
                                 preferenceDomain: GuardIdentity.app, homeURL: home,
                                 identity: item.identity)
        try preflight(plan)
        return plan
    }

    static func remove(_ plan: UninstallPlan, safety: UninstallSafetyChecks) throws -> UninstallReport {
        // This acknowledgment must happen before preferences, journals, or the bundle are removed.
        try safety.verifyRestoredAndUnregistered()
        try preflight(plan)
        var removed: [String] = []
        var currentPath = plan.homeURL.appendingPathComponent("Library/Preferences/\(GuardIdentity.app).plist")
        do {
            try safety.clearPreferences()
            for url in plan.userDataURLs {
                currentPath = url
                try validateDataPath(url, home: plan.homeURL)
                if try metadata(url) != nil {
                    try FileManager.default.removeItem(at: url)
                    removed.append(url.path)
                }
            }
            currentPath = plan.applicationURL
            try validateApplication(plan)
            try FileManager.default.removeItem(at: plan.applicationURL)
            removed.append(plan.applicationURL.path)
            return UninstallReport(removedPaths: removed, applicationRemoved: true)
        } catch let error as UninstallFailure {
            throw UninstallFailure(issues: error.issues, removedPaths: removed + error.removedPaths)
        } catch {
            let remaining = (plan.userDataURLs + [plan.applicationURL]).filter {
                $0.path != currentPath.path && (try? metadata($0)) != nil
            }
            let issues = [UninstallIssue(path: currentPath.path, message: "Removal did not finish: \(error.localizedDescription)")]
                + remaining.map { UninstallIssue(path: $0.path, message: "This item remains because uninstall did not finish.") }
            throw UninstallFailure(issues: issues, removedPaths: removed)
        }
    }

    private static func ownedDataURLs(home: URL) -> [URL] {
        ["Library/Preferences/\(GuardIdentity.app).plist",
         "Library/Caches/\(GuardIdentity.app)",
         "Library/Application Support/\(GuardIdentity.app)",
         "Library/Saved Application State/\(GuardIdentity.app).savedState"]
            .map { home.appendingPathComponent($0) }
    }

    private static func preflight(_ plan: UninstallPlan) throws {
        try validateApplication(plan)
        try validateRemovableTree(plan.applicationURL)
        for url in plan.userDataURLs {
            try validateDataPath(url, home: plan.homeURL)
            if try metadata(url) != nil { try validateRemovableTree(url) }
        }
    }

    private static func validateApplication(_ plan: UninstallPlan) throws {
        guard let item = try metadata(plan.applicationURL), item.kind == S_IFDIR,
              item.identity == plan.identity,
              plan.applicationURL.resolvingSymlinksInPath().path == plan.applicationURL.path else {
            throw failure(plan.applicationURL, "The application moved or changed after uninstall was prepared. Nothing at the replacement path will be removed.")
        }
    }

    private static func validateDataPath(_ url: URL, home: URL) throws {
        guard ownedDataURLs(home: home).contains(where: { $0.path == url.path }), contains(home, url) else {
            throw failure(url, "This path is outside Mamori's fixed cleanup list.")
        }
        var component = home
        for name in url.pathComponents.dropFirst(home.pathComponents.count) {
            component.appendPathComponent(name)
            if let item = try metadata(component) {
                guard item.kind != S_IFLNK else {
                    throw failure(component, "A symbolic link prevents safe cleanup. Its destination will not be removed.")
                }
                if component.path == url.path, item.owner != getuid() {
                    throw failure(component, "This user-data item belongs to another account and will not be removed.")
                }
            }
        }
    }

    private static func validateRemovableTree(_ url: URL) throws {
        let fm = FileManager.default
        guard fm.isDeletableFile(atPath: url.path) else {
            throw failure(url, "This item cannot be removed by your account. No administrator deletion is attempted.")
        }
        guard try metadata(url)?.kind == S_IFDIR else { return }
        var enumerationIssue: UninstallIssue?
        guard let entries = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { child, error in
            enumerationIssue = UninstallIssue(path: child.path, message: error.localizedDescription)
            return false
        }) else { throw failure(url, "This directory could not be inspected safely.") }
        for case let child as URL in entries {
            guard fm.isDeletableFile(atPath: child.path) else {
                throw failure(child, "This item cannot be removed by your account. The application was kept for retry.")
            }
        }
        if let enumerationIssue { throw UninstallFailure(issues: [enumerationIssue], removedPaths: []) }
    }

    private struct Metadata {
        let identity: UninstallFileIdentity
        let kind: mode_t
        let owner: uid_t
    }

    private static func metadata(_ url: URL) throws -> Metadata? {
        var value = stat()
        guard lstat(url.path, &value) == 0 else {
            if errno == ENOENT { return nil }
            throw failure(url, String(cString: strerror(errno)))
        }
        return Metadata(identity: UninstallFileIdentity(device: UInt64(value.st_dev), inode: UInt64(value.st_ino)),
                        kind: value.st_mode & S_IFMT, owner: value.st_uid)
    }

    private static func contains(_ parent: URL, _ child: URL) -> Bool {
        child.path == parent.path || child.path.hasPrefix(parent.path + "/")
    }

    private static func failure(_ url: URL, _ message: String) -> UninstallFailure {
        UninstallFailure(issues: [UninstallIssue(path: url.path, message: message)], removedPaths: [])
    }
}
