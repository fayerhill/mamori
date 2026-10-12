import AppKit
import SwiftUI

enum Screen: String { case home, settings, applications, connection, awake }

struct MamoriView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Theme.background
            Group {
                switch model.screen {
                case .home: home
                case .settings: settings
                case .applications: applications
                case .connection: connection
                case .awake: awake
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: Theme.width, height: Theme.height)
        .foregroundStyle(Theme.foreground)
        .font(.system(size: 12))
        .tint(Theme.accent)
        .alert(model.t(.error), isPresented: $model.showError) {
            Button(model.t(.done), role: .cancel) {}
        } message: { Text(model.errorMessage) }
        .confirmationDialog(model.t(.completeUninstall), isPresented: $model.showUninstallConfirmation, titleVisibility: .visible) {
            Button(model.t(.uninstallConfirm), role: .destructive) { model.completeUninstall() }
            Button(model.t(.cancel), role: .cancel) {}
        } message: { Text(model.t(.uninstallExplanation)) }
    }

    private var home: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mamori").font(.system(size: 15, weight: .semibold))
                    Text(model.compactStatus).font(.system(size: 11))
                        .foregroundStyle(model.needsAttention ? Theme.warning : Theme.secondary)
                        .accessibilityIdentifier("guard-status")
                }
                Spacer()
                if model.isDemo {
                    Text(model.t(.preview)).font(.system(size: 10))
                        .foregroundStyle(Theme.secondary)
                        .help(model.t(.previewNotice))
                }
            }.padding(.bottom, 12)
            Hairline()
            Button { model.screen = .connection } label: {
                HStack(spacing: 10) {
                    rowIcon("globe")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.vpnName).font(.system(size: 12))
                        Text(model.vpnSummary).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }.frame(height: 40)
            }.buttonStyle(.plain).accessibilityIdentifier("connection-details")
            Hairline()
            HStack(spacing: 10) {
                rowIcon("laptopcomputer")
                Button { model.screen = .awake } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.t(.keepAwake)).font(.system(size: 12)).lineLimit(1).minimumScaleFactor(0.8)
                        Text(model.awakeCompactSummary).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityIdentifier("awake-options")
                Toggle(model.t(.keepAwake), isOn: Binding(get: { model.awakeEnabled }, set: model.setAwake))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    .disabled(!model.canConfigure)
                    .accessibilityIdentifier("keep-awake-toggle")
            }.frame(height: 42)
            Hairline()
            HStack(alignment: .top, spacing: 10) {
                rowIcon("square.grid.2x2").padding(.top, 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.t(.autoQuit)).font(.system(size: 12))
                    Button(model.t(.chooseApps) + (model.selectedAppIDs.isEmpty ? "" : " · \(model.selectedAppIDs.count)")) {
                        model.refreshApps(); model.screen = .applications
                    }.font(.system(size: 10)).buttonStyle(.borderless)
                        .accessibilityIdentifier("choose-apps")
                }.padding(.top, 3)
                Spacer(minLength: 2)
                Toggle(model.t(.autoQuit), isOn: Binding(get: { model.autoQuitEnabled }, set: model.setAutoQuit))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    .disabled(!model.canConfigure)
                    .accessibilityIdentifier("auto-quit-toggle").padding(.top, 5)
            }.padding(.vertical, 8).help(model.t(.appsExplanation))
            Hairline()
            Button { model.toggleGuard() } label: {
                Text(model.primaryTitle).frame(maxWidth: .infinity)
            }.font(.system(size: 13, weight: .medium))
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(model.guardIsActive ? Theme.stopAccent : Theme.accent).padding(.top, 12)
                .disabled(model.busy).opacity(model.busy ? 0.6 : 1)
                .accessibilityIdentifier("guard-action")
            HStack {
                Button { model.screen = .settings } label: {
                    Label(model.t(.settings), systemImage: "gearshape").labelStyle(.titleAndIcon)
                }.accessibilityIdentifier("settings")
                Spacer()
                Button { model.requestQuit() } label: {
                    Label(model.t(.restoreQuit), systemImage: "power")
                }.accessibilityIdentifier("restore-and-quit")
            }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Theme.secondary)
                .padding(.top, 14)
        }
    }

    private func rowIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 14))
            .foregroundStyle(Theme.secondary).frame(width: 18).accessibilityHidden(true)
    }

    private func header(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button { model.screen = .home } label: {
                    Image(systemName: "chevron.left")
                }.buttonStyle(.borderless).accessibilityLabel(model.t(.back))
                    .accessibilityIdentifier("back")
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            Hairline()
        }.padding(.bottom, 12)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(model.t(.settings))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 9) {
                        sectionLabel(.language)
                        Picker(model.t(.language), selection: $model.language) {
                            ForEach(AppLanguage.allCases) { Text($0.name).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented).accessibilityIdentifier("language-picker")
                            .disabled(!model.canConfigure)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel(.networkProtection)
                        if !model.isDemo {
                            Text(model.helperAvailable ? model.t(.helperReady) : model.t(.helperNeeded))
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                        Button(model.t(.configure)) { model.screen = .connection }
                            .buttonStyle(.borderless).accessibilityIdentifier("configure-protection")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(model.t(.forceQuit), isOn: $model.forceQuitEnabled).toggleStyle(.switch)
                            .font(.system(size: 13)).accessibilityIdentifier("force-quit-toggle")
                            .disabled(!model.canConfigure)
                    }.help(model.t(.forceHelp))
                    if model.isDemo {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionLabel(.simulation)
                            Button(model.t(model.vpnConnected ? .simulateLoss : .simulateRecovery)) { model.simulateVPN(!model.vpnConnected) }
                                .buttonStyle(.borderless).accessibilityIdentifier("simulate-vpn")
                            Button(model.t(.resetDemo)) { model.resetDemo() }.buttonStyle(.borderless)
                                .accessibilityIdentifier("reset-preview")
                        }
                    }
                    Hairline()
                    Button(model.t(model.uninstallInProgress ? .uninstalling : .completeUninstall), role: .destructive) {
                        model.showUninstallConfirmation = true
                    }.buttonStyle(.borderless).disabled(model.busy)
                        .accessibilityIdentifier("complete-uninstall")
                    Text(model.t(.build)).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }.padding(.bottom, 10)
            }.scrollIndicators(.hidden)
        }
    }

    private var awake: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(model.t(.keepAwake))
            ScrollView {
            VStack(alignment: .leading, spacing: 0) {
            Toggle(model.t(.keepAwake), isOn: Binding(get: { model.awakeEnabled }, set: model.setAwake))
                .toggleStyle(.switch).controlSize(.small).padding(.bottom, 14)
            Picker(model.t(.customDuration), selection: $model.awakeMode) {
                Text(model.t(.always)).tag(AwakeMode.always)
                Text(model.t(.customDuration)).tag(AwakeMode.duration)
            }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("awake-mode")
            if model.awakeMode == .duration {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.t(.durationLabel)).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    HStack {
                        TextField("60", value: $model.awakeMinutes, formatter: Self.minutesFormatter)
                            .textFieldStyle(.roundedBorder).frame(width: 94)
                            .accessibilityIdentifier("awake-minutes")
                        Text(model.t(.minutes)).foregroundStyle(Theme.secondary)
                        Spacer()
                    }
                    HStack(spacing: 16) {
                        ForEach([30, 60, 120], id: \.self) { minutes in
                            Button("\(minutes)") { model.awakeMinutes = minutes }.buttonStyle(.borderless)
                        }
                    }
                }.padding(.top, 12)
            }
            Text(model.awakeSummary).foregroundStyle(Theme.accent).padding(.top, 14)
            }.help(model.t(.wakeHelp))
            .disabled(!model.canConfigure)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
            }.scrollIndicators(.hidden)
            doneButton.padding(.top, 12)
        }
    }

    private var applications: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(model.t(.chooseApps))
            TextField(model.t(.searchApps), text: $model.appSearch)
                .textFieldStyle(.roundedBorder).padding(.bottom, 9)
                .accessibilityIdentifier("search-apps")
            HStack {
                Text("\(model.selectedAppIDs.count) · \(model.t(.selectedApps))").font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Button(model.t(.refresh)) { model.refreshApps(force: true) }.buttonStyle(.borderless).font(.system(size: 12))
            }.padding(.bottom, 10)
            Hairline()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.filteredApps.isEmpty {
                        Text(model.t(.noApps)).foregroundStyle(Theme.secondary).padding(.vertical, 35)
                    }
                    ForEach(model.filteredApps) { app in
                        HStack(alignment: .center, spacing: 8) {
                            Toggle(app.name, isOn: Binding(get: { model.selectedAppIDs.contains(app.id) }, set: { model.selectApp(app.id, selected: $0) }))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .accessibilityIdentifier("select-app-\(app.id)")
                                .accessibilityHint(Text(model.applicationNotes[app.id] ?? (app.isRunning ? "" : model.t(.notRunning))))
                            HStack(spacing: 12) {
                                if let icon = model.icon(for: app) {
                                    Image(nsImage: icon).resizable().frame(width: 27, height: 27)
                                } else {
                                    Image(systemName: "app").font(.system(size: 23)).frame(width: 27, height: 27).foregroundStyle(Theme.accent)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(app.name).font(.system(size: 14))
                                    if let status = model.applicationNotes[app.id] {
                                        Text(status).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                    } else if !app.isRunning {
                                        Text(model.t(.notRunning)).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard model.canConfigure else { return }
                                    model.selectApp(app.id, selected: !model.selectedAppIDs.contains(app.id))
                                }
                                .accessibilityHidden(true)
                        }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .disabled(!model.canConfigure)
                        Hairline()
                    }
                }
            }.scrollIndicators(.hidden)
            doneButton.padding(.top, 9)
        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(model.t(.connectionDetails))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image(systemName: "globe").font(.system(size: 16)).foregroundStyle(Theme.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.vpnName).font(.system(size: 13, weight: .medium))
                            Text(model.vpnSummary).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Button(model.t(.refresh)) { model.detectConnection() }.buttonStyle(.borderless).font(.system(size: 12))
                            .disabled(!model.canConfigure || model.guardIsActive)
                    }
                    Hairline()
                    if !model.isDemo {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.helperSummary).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            if !model.helperAvailable {
                                Button(model.t(.installHelper)) { model.installHelper() }.buttonStyle(.borderless)
                                    .disabled(!model.canConfigure || !model.canInstallHelper)
                                    .accessibilityIdentifier("install-helper")
                                if model.canInstallHelper {
                                    Button(model.t(.approveHelper)) { model.approveHelper() }.buttonStyle(.borderless)
                                        .disabled(!model.canConfigure)
                                }
                            } else {
                                Button(model.t(.detectConnection)) { model.detectConnection() }.buttonStyle(.borderless)
                                    .disabled(!model.canConfigure || model.guardIsActive)
                                    .accessibilityIdentifier("detect-connection")
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel(.tunnel)
                        TextField("utun…", text: $model.tunnelInterface).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("tunnel-interface")
                        sectionLabel(.gateways)
                        TextField("203.0.113.10", text: $model.gatewayAddresses).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("gateway-addresses")
                        Text(model.t(.gatewayHelp)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }.disabled(model.guardIsActive || !model.canConfigure)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.t(.safetyNotice)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Text(model.t(.manualDisconnectProtection)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                    DisclosureGroup(model.t(.details)) {
                        Text(model.connectionEvidence.joined(separator: "\n"))
                            .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }.font(.system(size: 12))
                    if model.isDemo {
                        Button(model.t(model.vpnConnected ? .simulateLoss : .simulateRecovery)) { model.simulateVPN(!model.vpnConnected) }
                            .buttonStyle(.borderless).accessibilityIdentifier("simulate-vpn")
                        Text(model.t(.previewNotice)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    } else if model.helperAvailable {
                        Button(model.t(.removeHelper)) { model.removeHelper() }.buttonStyle(.borderless).disabled(model.busy)
                    }
                }.padding(.bottom, 10)
            }.scrollIndicators(.hidden)
        }
    }

    private var doneButton: some View {
        HStack {
            Spacer()
            Button(model.t(.done)) { model.screen = .home }
                .buttonStyle(.borderedProminent).controlSize(.regular)
        }
    }

    private func sectionLabel(_ copy: Copy) -> some View {
        Text(model.t(copy)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.foreground)
    }

    private static let minutesFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 10_080
        formatter.allowsFloats = false
        return formatter
    }()
}
