import Foundation
import Testing
@testable import MamoriSystem
import MamoriCore

/// These tests only remove their own UUID-named temporary fixture directory.
/// They never call production service checks, preferences, or Bundle.main cleanup.
@MainActor struct UninstallServiceTests {
    @Test func planContainsOnlyCurrentAppAndExactOwnedUserPaths() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let plan = try UninstallService.prepare(context: fixture.context)
        #expect(plan.applicationURL.path == fixture.app.path)
        #expect(plan.preferenceDomain == GuardIdentity.app)
        #expect(plan.userDataURLs.map(\.path) == [
            "Library/Preferences/com.mamori.app.plist",
            "Library/Caches/com.mamori.app",
            "Library/Application Support/com.mamori.app",
            "Library/Saved Application State/com.mamori.app.savedState"
        ].map { fixture.home.appendingPathComponent($0).path })
    }

    @Test func previewAndNonMamoriBundlesCannotPrepare() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let context = UninstallContext(bundleURL: fixture.app, executableURL: fixture.executable,
                                       bundleIdentifier: "com.mamori.preview", homeURL: fixture.home)
        #expect(throws: UninstallFailure.self) { try UninstallService.prepare(context: context) }
        #expect(FileManager.default.fileExists(atPath: fixture.app.path))
    }

    @Test func symlinkApplicationCannotPrepare() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let link = fixture.root.appendingPathComponent("Linked.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.app)
        let context = UninstallContext(bundleURL: link, executableURL: fixture.executable,
                                       bundleIdentifier: GuardIdentity.app, homeURL: fixture.home)
        #expect(throws: UninstallFailure.self) { try UninstallService.prepare(context: context) }
    }

    @Test func redirectedDataDirectoryIsNeverFollowed() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let caches = fixture.home.appendingPathComponent("Library/Caches")
        let unrelated = fixture.root.appendingPathComponent("Unrelated")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let sentinel = unrelated.appendingPathComponent("com.mamori.app")
        try Data("unrelated".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: caches, withDestinationURL: unrelated)
        #expect(throws: UninstallFailure.self) { try UninstallService.prepare(context: fixture.context) }
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "unrelated")
    }

    @Test func unresolvedGuardPreventsAllDeletionAndPreferenceCleanup() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let plan = try UninstallService.prepare(context: fixture.context)
        var preferencesCleared = false
        let checks = UninstallSafetyChecks(verifyRestoredAndUnregistered: {
            throw TestFailure.guardStillActive
        }, clearPreferences: { preferencesCleared = true })
        #expect(throws: TestFailure.self) { try UninstallService.remove(plan, safety: checks) }
        #expect(!preferencesCleared)
        #expect(FileManager.default.fileExists(atPath: fixture.app.path))
    }

    @Test func replacedBundleIsKeptEvenAfterHelperCleanup() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let plan = try UninstallService.prepare(context: fixture.context)
        try FileManager.default.moveItem(at: fixture.app, to: fixture.root.appendingPathComponent("Original.app"))
        try FileManager.default.createDirectory(at: fixture.app, withIntermediateDirectories: true)
        let sentinel = fixture.app.appendingPathComponent("do-not-remove")
        try Data("replacement".utf8).write(to: sentinel)
        var preferencesCleared = false
        let checks = UninstallSafetyChecks(verifyRestoredAndUnregistered: {}, clearPreferences: { preferencesCleared = true })
        #expect(throws: UninstallFailure.self) { try UninstallService.remove(plan, safety: checks) }
        #expect(!preferencesCleared)
        #expect(FileManager.default.fileExists(atPath: sentinel.path))
    }

    @Test func preferenceFailureKeepsTheApplicationForRetry() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let plan = try UninstallService.prepare(context: fixture.context)
        let checks = UninstallSafetyChecks(verifyRestoredAndUnregistered: {}, clearPreferences: {
            throw TestFailure.preferencesUnavailable
        })
        #expect(throws: UninstallFailure.self) { try UninstallService.remove(plan, safety: checks) }
        #expect(FileManager.default.fileExists(atPath: fixture.app.path))
    }

    @Test func permissionFailureIsDetectedBeforeClearingPreferences() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let plan = try UninstallService.prepare(context: fixture.context)
        let directory = fixture.executable.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        var preferencesCleared = false
        let checks = UninstallSafetyChecks(verifyRestoredAndUnregistered: {}, clearPreferences: { preferencesCleared = true })
        #expect(throws: UninstallFailure.self) { try UninstallService.remove(plan, safety: checks) }
        #expect(!preferencesCleared)
        #expect(FileManager.default.fileExists(atPath: fixture.app.path))
    }

    @Test func dataPathRedirectedAfterPreparationIsRejectedBeforePreferences() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let plan = try UninstallService.prepare(context: fixture.context)
        let external = fixture.root.appendingPathComponent("ExternalCache")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.home.appendingPathComponent("Library/Caches"), withDestinationURL: external)
        var preferencesCleared = false
        let checks = UninstallSafetyChecks(verifyRestoredAndUnregistered: {}, clearPreferences: { preferencesCleared = true })
        #expect(throws: UninstallFailure.self) { try UninstallService.remove(plan, safety: checks) }
        #expect(!preferencesCleared)
        #expect(FileManager.default.fileExists(atPath: external.path))
    }

    @Test func removesOnlyFixtureAppAndOwnedDataAfterSafetyAcknowledgment() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let preferences = fixture.home.appendingPathComponent("Library/Preferences/com.mamori.app.plist")
        let cache = fixture.home.appendingPathComponent("Library/Caches/com.mamori.app")
        try FileManager.default.createDirectory(at: preferences.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: preferences)
        try Data("fixture".utf8).write(to: cache.appendingPathComponent("cache"))
        let unrelated = fixture.home.appendingPathComponent("Library/Preferences/com.other.app.plist")
        try Data("keep".utf8).write(to: unrelated)
        try FileManager.default.createSymbolicLink(at: cache.appendingPathComponent("external-link"), withDestinationURL: unrelated)
        let plan = try UninstallService.prepare(context: fixture.context)
        var order: [String] = []
        let checks = UninstallSafetyChecks(verifyRestoredAndUnregistered: { order.append("restored") },
                                          clearPreferences: { order.append("preferences") })
        let result = try UninstallService.remove(plan, safety: checks)
        #expect(order == ["restored", "preferences"])
        #expect(result.applicationRemoved)
        #expect(Set(result.removedPaths) == Set([preferences.path, cache.path, fixture.app.path]))
        #expect(!FileManager.default.fileExists(atPath: fixture.app.path))
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep")
        #expect(FileManager.default.fileExists(atPath: fixture.home.appendingPathComponent("Library/Preferences").path))
    }

    private enum TestFailure: Error { case guardStillActive, preferencesUnavailable }

    private struct Fixture {
        let root: URL
        let home: URL
        let app: URL
        var executable: URL { app.appendingPathComponent("Contents/MacOS/Mamori") }
        var context: UninstallContext {
            UninstallContext(bundleURL: app, executableURL: executable,
                             bundleIdentifier: GuardIdentity.app, homeURL: home)
        }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("MamoriUninstallTest-\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            home = root.appendingPathComponent("Home")
            app = root.appendingPathComponent("Mamori.app")
            try FileManager.default.createDirectory(at: home.appendingPathComponent("Library"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            try Data("This is an inert test fixture, not an executable.".utf8).write(to: executable)
            let info = ["CFBundleIdentifier": GuardIdentity.app, "CFBundleExecutable": "Mamori", "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: app.appendingPathComponent("Contents/Info.plist"))
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }
}
