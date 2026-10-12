import AppKit
import Combine
import Foundation
import MamoriCore
import MamoriSystem

enum AwakeMode: String { case always, duration }

@MainActor
final class AppModel: ObservableObject {
    let isDemo: Bool
    @Published var screen = Screen.home
    @Published var appSearch = ""
    @Published var language: AppLanguage {
        didSet { if !isDemo, !uninstallRequested { preferences.set(language.rawValue, forKey: "language") } }
    }
    @Published private(set) var session = SessionState()
    @Published private(set) var apps: [ApplicationSnapshot] = []
    @Published private(set) var applicationNotes: [String: String] = [:]
    @Published private(set) var vpnConnected = false
    @Published private(set) var vpnState = VPNConnectionState.unconfirmed
    @Published private(set) var connectionEvidence: [String] = []
    @Published private(set) var backend = GuardStatus(phase: .unavailable, message: "Not checked")
    @Published private(set) var remainingSeconds = 0
    @Published private var wakeReleaseFailed = false
    @Published private var setupBusy = false
    @Published private(set) var uninstallInProgress = false
    @Published var showUninstallConfirmation = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var tunnelInterface = ""
    @Published var gatewayAddresses = ""
    @Published var forceQuitEnabled = false {
        didSet { if !forceQuitEnabled { cancelPendingQuits() } }
    }
    @Published var awakeMode = AwakeMode.always {
        didSet { if awakeEnabled { applyAwakeChoice() } }
    }
    @Published var awakeMinutes = 60 {
        didSet {
            if awakeMinutes < 1 || awakeMinutes > 10_080 { awakeMinutes = min(10_080, max(1, awakeMinutes)) }
            if awakeEnabled, awakeMode == .duration { applyAwakeChoice() }
        }
    }
    var onExit: (() -> Void)?
    var onStatusChange: (() -> Void)?

    private let preferences: UserDefaults
    private let power: PowerService?
    private let applications: ApplicationsService?
    private let catalog: ApplicationsService
    private let observer: VPNObserver?
    private let guardClient: GuardClient?
    private var pollTask: Task<Void, Never>?
    private var wakeTimeout: Task<Void, Never>?
    private var quitTasks: [String: Task<Void, Never>] = [:]
    private var quittingApplications: [String: ApplicationSnapshot] = [:]
    private var setupTask: Task<Void, Never>?
    private var activeWakeTicket: UInt64?
    private var wakeDeadline: ContinuousClock.Instant?
    private var rememberedApps: [String: ApplicationSnapshot] = [:]
    private var checkingBackend = false
    private var backendCheckTask: Task<GuardStatus, Never>?
    private var uninstallRequested = false
    private var uninstallPlan: UninstallPlan?
    private var backendRequest: UInt64 = 0

    init(demo: Bool = ProcessInfo.processInfo.arguments.contains("--demo") || Bundle.main.bundleIdentifier == "com.mamori.preview") {
        isDemo = demo
        preferences = demo ? UserDefaults(suiteName: "com.mamori.preview.ephemeral")! : .standard
        let arguments = ProcessInfo.processInfo.arguments
        let argumentLanguage: String? = arguments.firstIndex(of: "--language").flatMap {
            arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
        }
        language = AppLanguage(rawValue: argumentLanguage ?? (demo ? "en" : preferences.string(forKey: "language") ?? "en")) ?? .english
        power = demo ? nil : PowerService()
        let applicationService = ApplicationsService()
        catalog = applicationService
        applications = demo ? nil : applicationService
        observer = demo ? nil : VPNObserver()
        guardClient = demo ? nil : GuardClient()
        if demo {
            resetDemo()
        } else {
            let identifiers = Set(preferences.stringArray(forKey: "selectedApplications") ?? [])
            send(.setSelectedApplications(identifiers))
            refreshConnection()
            refreshApps()
            Task { [weak self] in await self?.checkBackend() }
        }
        startPolling()
    }

    func t(_ copy: Copy) -> String { copy.text(language) }
    var awakeEnabled: Bool { session.wakeActive || session.wakeAcquiring || wakeReleaseFailed }
    var autoQuitEnabled: Bool { session.autoQuitEnabled }
    var selectedAppIDs: Set<String> { session.selectedApplicationIDs }
    var helperAvailable: Bool { isDemo || backend.helperAvailable }
    var busy: Bool { setupBusy || uninstallInProgress || session.phase == .arming || session.phase == .restoring }
    var canConfigure: Bool { !busy && !session.wantsToQuit }
    var canInstallHelper: Bool { !isDemo && guardClient?.canInstall == true }
    var guardIsActive: Bool { session.phase == .protected || session.phase == .blocked }
    var needsAttention: Bool { session.phase == .fault || session.phase == .blocked }
    var vpnName: String { "GlobalProtect" }
    var vpnSummary: String {
        t(vpnState == .connected ? .vpnDetected : vpnState == .disconnected ? .vpnDisconnected : .vpnUnconfirmed)
    }
    var title: String {
        switch session.phase {
        case .idle: t(.ready)
        case .arming: t(.working)
        case .protected: t(.protected)
        case .blocked: t(.blocked)
        case .fault: t(.attention)
        case .restoring: t(.shuttingDown)
        }
    }
    var subtitle: String {
        switch session.phase {
        case .idle: t(.inactive)
        case .arming, .restoring: t(.pending)
        case .protected: t(.protectedDetail)
        case .blocked: t(.blockedDetail)
        case .fault: t(.error)
        }
    }
    var compactStatus: String { session.phase == .idle ? t(.inactive) : title }
    var filteredApps: [ApplicationSnapshot] {
        let query = appSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.bundleIdentifier.localizedCaseInsensitiveContains(query) }
    }
    var heroSymbol: String {
        switch session.phase {
        case .protected: "checkmark.shield"
        case .blocked, .fault: "exclamationmark.shield"
        default: "shield.lefthalf.filled"
        }
    }
    var primaryTitle: String { t(guardIsActive ? .stop : session.phase == .fault || session.wantsToQuit ? .retry : .start) }
    var awakeSummary: String {
        guard awakeEnabled else { return t(.awakeOff) }
        if awakeMode == .always { return "\(t(.always)) · \(t(.untilQuit))" }
        let minutes = max(0, remainingSeconds) / 60
        let seconds = max(0, remainingSeconds) % 60
        return "\(minutes):\(String(format: "%02d", seconds)) \(t(.remaining))"
    }
    var awakeCompactSummary: String {
        guard awakeEnabled else { return t(.off) }
        return awakeMode == .always ? t(.always) : awakeSummary
    }
    var autoQuitSummary: String {
        guard autoQuitEnabled else { return t(.off) }
        return selectedAppIDs.isEmpty ? t(.noSelection) : "\(selectedAppIDs.count) · \(t(.on))"
    }
    var helperSummary: String {
        if isDemo { return t(.previewNotice) }
        if guardClient?.canInstall != true { return t(.platformNotice) }
        return backend.helperAvailable ? t(.helperReady) : backend.message
    }

    func setAwake(_ enabled: Bool) {
        guard canConfigure else { return }
        if !enabled, wakeReleaseFailed {
            do {
                try power?.disable()
                wakeReleaseFailed = false
                activeWakeTicket = nil
            } catch { report(error.localizedDescription) }
        }
        if enabled { applyAwakeChoice() } else { send(.setKeepAwake(.off)) }
    }

    private func applyAwakeChoice() {
        let choice: KeepAwakeChoice = awakeMode == .always ? .whileAppRuns : .forDuration(seconds: Double(awakeMinutes * 60))
        send(.setKeepAwake(choice))
    }

    func setAutoQuit(_ enabled: Bool) {
        guard canConfigure else { return }
        send(.setAutoQuit(enabled))
    }

    func selectApp(_ id: String, selected: Bool) {
        guard !session.wantsToQuit else { return }
        var updated = selectedAppIDs
        if selected { updated.insert(id) } else { updated.remove(id) }
        send(.setSelectedApplications(updated))
        if !isDemo, !uninstallRequested { preferences.set(Array(updated).sorted(), forKey: "selectedApplications") }
    }

    func refreshApps(force: Bool = false) {
        // Catalog discovery is read-only in both modes. The preview never receives an action adapter.
        let installed = catalog.installed(refresh: force)
        for app in installed { rememberedApps[app.id] = app }
        let installedIDs = Set(installed.map(\.id))
        let missing = selectedAppIDs.subtracting(installedIDs).compactMap { rememberedApps[$0] }
        for app in installed where app.isRunning {
            if applicationNotes[app.id] == t(.notRunning) { applicationNotes.removeValue(forKey: app.id) }
        }
        apps = (installed + missing).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func icon(for app: ApplicationSnapshot) -> NSImage? {
        return NSWorkspace.shared.icon(forFile: app.bundleURL.path)
    }

    func refreshConnection() {
        guard !isDemo, !session.wantsToQuit, let snapshot = observer?.snapshot() else { return }
        recordConnectionEvidence(snapshot)
    }

    func recordConnectionEvidence(_ snapshot: VPNSnapshot) {
        let changed = vpnState != snapshot.state
        vpnState = snapshot.state
        vpnConnected = snapshot.isConnected
        connectionEvidence = snapshot.evidence + [backend.message]
        if !guardIsActive, !busy, let interface = snapshot.interface { tunnelInterface = interface }
        // Only the authenticated guard may claim enforcement or trigger app quitting.
        // Local tunnel evidence requests a fresh check; it cannot overwrite a blocked guard.
        if !isDemo, changed, guardIsActive { Task { [weak self] in await self?.checkBackend() } }
    }

    func toggleGuard() {
        guard !busy else { return }
        if session.wantsToQuit {
            if uninstallRequested { completeUninstall() }
            else { beginQuit() }
            return
        }
        if session.phase == .fault { send(.retryRestoration); return }
        if guardIsActive { send(.stopGuard); return }
        guard isDemo || helperAvailable else { screen = .connection; return }
        if !isDemo, !validateGuardInput() { return }
        send(.startGuard)
    }

    /// The observer is advisory. The authenticated helper verifies the actual
    /// GlobalProtect connection before making any firewall changes.
    func validateGuardInput() -> Bool {
        do {
            try GuardPolicy.validate(guardConfiguration)
            return true
        } catch {
            screen = .connection
            switch error as? GuardPolicyError {
            case .invalidTunnel: report(t(.tunnelHelp))
            case .noGateway: report(t(.gatewayRequired))
            case .invalidGateway: report(t(.gatewayInvalid))
            default: report(error.localizedDescription)
            }
            return false
        }
    }

    private var guardConfiguration: GuardConfiguration {
        GuardConfiguration(
            tunnelInterface: tunnelInterface.trimmingCharacters(in: .whitespacesAndNewlines),
            gatewayAddresses: parsedGateways
        )
    }

    private var parsedGateways: [String] {
        gatewayAddresses.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
    }

    func installHelper() {
        guard !isDemo, !busy, !session.wantsToQuit, let guardClient else { return }
        setupBusy = true
        setupTask = Task { [weak self] in
            _ = await self?.backendCheckTask?.value
            let result = await guardClient.install()
            guard let self else { return }
            defer { setupBusy = false }
            guard !session.wantsToQuit else { return }
            backend = result
            connectionEvidence = observer?.snapshot().evidence ?? []
            connectionEvidence.append(backend.message)
            if !backend.helperAvailable { report(backend.message) }
            else { await discoverConnection(using: guardClient) }
        }
    }

    func approveHelper() { guardClient?.openApprovalSettings() }

    func detectConnection() {
        guard canConfigure, !guardIsActive else { return }
        refreshConnection()
        guard !isDemo, let guardClient, helperAvailable else { return }
        setupBusy = true
        setupTask = Task { [weak self] in
            guard let self else { return }
            defer { setupBusy = false }
            await discoverConnection(using: guardClient)
        }
    }

    private func discoverConnection(using client: GuardClient) async {
        let discovery = await client.discoverConfiguration()
        guard !session.wantsToQuit else { return }
        connectionEvidence.append(discovery.message)
        if let configuration = discovery.configuration {
            tunnelInterface = configuration.tunnelInterface
            gatewayAddresses = configuration.gatewayAddresses.joined(separator: ", ")
        } else { report(discovery.message) }
    }

    func removeHelper() {
        guard !isDemo, !busy, !session.wantsToQuit, let guardClient else { return }
        send(.setAutoQuit(false))
        setupBusy = true
        setupTask = Task { [weak self] in
            _ = await self?.backendCheckTask?.value
            let result = await guardClient.uninstall()
            guard let self else { return }
            defer { setupBusy = false }
            guard !session.wantsToQuit else { return }
            backend = result
            if backend.phase == .fault { report(backend.message) }
            else if guardIsActive { send(.stopGuard) }
        }
    }

    func requestQuit() { NSApplication.shared.terminate(nil) }

    func completeUninstall() {
        guard !busy else { return }
        if isDemo {
            report(t(.uninstallPreview))
            return
        }
        do {
            if uninstallPlan == nil { uninstallPlan = try UninstallService.prepare() }
        } catch {
            report(error.localizedDescription)
            return
        }
        uninstallRequested = true
        uninstallInProgress = true
        NSApplication.shared.disableRelaunchOnLogin()
        for window in NSApplication.shared.windows { window.isRestorable = false }
        beginQuit()
    }

    private func finishUninstall() async {
        guard let guardClient, let plan = uninstallPlan else {
            uninstallInProgress = false
            report(t(.uninstallFailed))
            return
        }
        backend = await guardClient.uninstall()
        guard backend.phase == .inactive else {
            uninstallInProgress = false
            report(backend.message)
            return
        }
        do {
            _ = try UninstallService.remove(plan)
            onExit?()
        } catch {
            uninstallInProgress = false
            report(error.localizedDescription)
        }
    }

    func beginQuit() {
        backendRequest &+= 1
        pollTask?.cancel()
        pollTask = nil
        cancelPendingQuits()
        send(.normalQuit)
    }

    func simulateVPN(_ connected: Bool) {
        guard isDemo, !session.wantsToQuit else { return }
        vpnConnected = connected
        vpnState = connected ? .connected : .disconnected
        connectionEvidence = ["Simulated GlobalProtect state. No real network observation or action is performed."]
        send(.vpnChanged(connected ? .connected : .disconnected))
    }

    func resetDemo() {
        guard isDemo else { return }
        cancelPendingQuits()
        wakeTimeout?.cancel()
        wakeDeadline = nil
        session = SessionState()
        apps = []
        appSearch = ""
        applicationNotes = [:]
        refreshApps()
        backend = GuardStatus(phase: .inactive, message: "Simulated service", helperAvailable: true)
        tunnelInterface = "utun-preview"
        gatewayAddresses = "192.0.2.10"
        awakeMode = .always
        forceQuitEnabled = false
        simulateVPN(true)
        setAwake(true)
        screen = .home
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            var cycle = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                updateCountdown()
                cycle += 1
                refreshConnection()
                if cycle.isMultiple(of: 2) {
                    if screen == .applications { refreshApps() }
                    reconcileApplicationQuits()
                    if !isDemo { await checkBackend() }
                }
            }
        }
    }

    private func checkBackend() async {
        guard !checkingBackend, !session.wantsToQuit, !busy, let guardClient else { return }
        checkingBackend = true
        let request = backendRequest
        let operation = session.guardOperation
        let check = Task { await guardClient.check() }
        backendCheckTask = check
        let result = await check.value
        backendCheckTask = nil
        checkingBackend = false
        guard !session.wantsToQuit, !busy, request == backendRequest,
              operation == session.guardOperation else { return }
        backend = result
        if session.phase == .idle, backend.isEnforcing || backend.phase == .fault {
            send(.existingGuardNeedsRestoration("An existing Mamori session needs restoration before starting again."))
        }
        if guardIsActive {
            if backend.isEnforcing {
                send(.vpnChanged(backendSignal))
            } else {
                report(backend.message)
                send(.backendFailed(backend.message))
            }
        }
    }

    private func send(_ event: SessionEvent) {
        let effects = SessionReducer.reduce(&session, event)
        if session.phase == .fault { uninstallInProgress = false }
        for effect in effects { execute(effect) }
        onStatusChange?()
    }

    private var backendSignal: VPNConnectionSignal {
        if backend.phase == .protected { return .connected }
        return backend.vpnState == .disconnected ? .disconnected : .unverified
    }

    private func execute(_ effect: SessionEffect) {
        switch effect {
        case .activateGuard(let operation):
            backendRequest &+= 1
            let configuration = guardConfiguration
            Task { [weak self] in
                guard let self else { return }
                if isDemo {
                    try? await Task.sleep(for: .milliseconds(200))
                    send(.guardActivationCompleted(operation: operation, result: .verified(vpnConnected ? .connected : .disconnected)))
                } else if let guardClient {
                    _ = await backendCheckTask?.value
                    backend = await guardClient.start(configuration: configuration)
                    let result: GuardActivationResult = backend.isEnforcing ? .verified(backendSignal) : .failed(backend.message)
                    send(.guardActivationCompleted(operation: operation, result: result))
                    if !backend.isEnforcing { report(backend.message) }
                }
            }
        case .restoreGuard(let operation):
            backendRequest &+= 1
            Task { [weak self] in
                guard let self else { return }
                if isDemo {
                    try? await Task.sleep(for: .milliseconds(100))
                    send(.restorationCompleted(operation: operation, success: true, message: nil))
                } else if let guardClient {
                    await setupTask?.value
                    _ = await backendCheckTask?.value
                    backend = await guardClient.stop()
                    let success = backend.phase == .inactive
                    send(.restorationCompleted(operation: operation, success: success, message: success ? nil : backend.message))
                    if !success { report(backend.message) }
                }
            }
        case .quitApplications(let ids, let ticket):
            refreshApps()
            let running = isDemo ? apps.filter(\.isRunning) : applications?.list() ?? []
            for id in ids {
                guard session.canPerformAutoQuit(id: id, ticket: ticket) else { continue }
                guard let app = running.first(where: { $0.id == id }) else {
                    send(.applicationDidQuit(id: id, ticket: ticket))
                    continue
                }
                if isDemo {
                    applicationNotes[id] = t(.quitRequested)
                    send(.applicationDidQuit(id: id, ticket: ticket))
                    continue
                }
                guard let applications else { continue }
                let result = applications.requestQuit(app)
                applicationNotes[id] = result == .requested ? t(.quitRequested) : result.rawValue
                if result == .requested { quittingApplications[id] = app }
                if result == .alreadyStopped { send(.applicationDidQuit(id: id, ticket: ticket)) }
                guard forceQuitEnabled, result == .requested else { continue }
                quitTasks[id]?.cancel()
                quitTasks[id] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled, let self, !session.wantsToQuit,
                          forceQuitEnabled, session.canPerformAutoQuit(id: id, ticket: ticket) else { return }
                    if applications.isRunning(app) {
                        let result = applications.forceQuit(app)
                        applicationNotes[id] = result == .requested ? t(.forceRequested) : result.rawValue
                    }
                    if !applications.isRunning(app) { send(.applicationDidQuit(id: id, ticket: ticket)) }
                    quitTasks.removeValue(forKey: id)
                }
            }
        case .cancelApplicationQuits(let ids):
            for id in ids {
                quitTasks.removeValue(forKey: id)?.cancel()
                quittingApplications.removeValue(forKey: id)
            }
        case .acquireWake(let ticket):
            do {
                try power?.enable()
                activeWakeTicket = ticket
                wakeReleaseFailed = false
                send(.wakeAcquisitionCompleted(ticket: ticket, success: true))
            } catch {
                send(.wakeAcquisitionCompleted(ticket: ticket, success: false))
                report(error.localizedDescription)
            }
        case .releaseWake(let ticket):
            guard ticket == activeWakeTicket else { break }
            do {
                try power?.disable()
                activeWakeTicket = nil
                wakeReleaseFailed = false
            } catch {
                wakeReleaseFailed = true
                report(error.localizedDescription)
            }
        case .scheduleWakeTimeout(let ticket, let seconds):
            wakeTimeout?.cancel()
            wakeDeadline = ContinuousClock.now.advanced(by: .seconds(seconds))
            remainingSeconds = Int(seconds)
            wakeTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self else { return }
                send(.wakeDurationElapsed(ticket: ticket))
            }
        case .cancelWakeTimeout:
            wakeTimeout?.cancel()
            wakeTimeout = nil
            wakeDeadline = nil
            remainingSeconds = 0
        case .exitApplication:
            cancelPendingQuits()
            wakeTimeout?.cancel()
            pollTask?.cancel()
            do { try power?.disable(); wakeReleaseFailed = false }
            catch {
                uninstallInProgress = false
                report(error.localizedDescription)
                return
            }
            if uninstallRequested {
                Task { [weak self] in await self?.finishUninstall() }
            } else { onExit?() }
        }
    }

    private func updateCountdown() {
        guard let deadline = wakeDeadline else { return }
        let remaining = ContinuousClock.now.duration(to: deadline).components
        remainingSeconds = max(0, Int(ceil(Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18)))
    }

    private func reconcileApplicationQuits() {
        guard let applications else { return }
        for (id, app) in quittingApplications where !applications.isRunning(app) {
            send(.applicationDidQuit(id: id, ticket: session.autoQuitTicket))
            applicationNotes[id] = t(.notRunning)
            quittingApplications.removeValue(forKey: id)
        }
    }

    private func cancelPendingQuits() {
        quitTasks.values.forEach { $0.cancel() }
        quitTasks.removeAll()
        quittingApplications.removeAll()
    }

    private func report(_ message: String) {
        errorMessage = message
        showError = true
    }
}
