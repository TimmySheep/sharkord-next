import SharkordCore
import SwiftUI

private enum PluginDetailTab: String, CaseIterable, Identifiable {
    case settings
    case permissions
    case commands
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings:
            return L10n.t("pluginSettingsTab", ns: "settings")
        case .permissions:
            return L10n.t("pluginPermissionsTab", ns: "settings")
        case .commands:
            return L10n.t("pluginCommandsTab", ns: "settings")
        case .logs:
            return L10n.t("pluginLogsTab", ns: "settings")
        }
    }
}

private enum PluginWorkspaceTab: String, CaseIterable, Identifiable {
    case installed
    case marketplace

    var id: String { rawValue }
}

private struct PluginCapabilitySelection {
    let mode: String
    let roleIds: [Int]
}

private struct PendingMarketplaceAction: Identifiable {
    let id = UUID()
    let pluginId: String
    let pluginName: String
    let version: String
    let isUpdate: Bool
}

struct PluginManagementView: View {
    @EnvironmentObject private var session: SharkordSession

    @State private var plugins: [PluginInfo] = []
    @State private var workspaceTab = PluginWorkspaceTab.installed
    @State private var marketplaceEntries: [MarketplacePluginEntry] = []
    @State private var marketplaceSearch = ""
    @State private var marketplaceError: String?
    @State private var isMarketplaceLoading = false
    @State private var hasLoadedMarketplace = false
    @State private var pendingMarketplaceAction: PendingMarketplaceAction?
    @State private var selected: PluginInfo?
    @State private var detailTab = PluginDetailTab.settings
    @State private var settings: PluginSettings?
    @State private var settingValues: [String: JSONValue] = [:]
    @State private var secretKeys = Set<String>()
    @State private var capabilities: [PluginCapability] = []
    @State private var capabilityValues: [String: PluginCapabilitySelection] = [:]
    @State private var commands: [PluginCommand] = []
    @State private var selectedCommandId = ""
    @State private var commandArguments: [String: String] = [:]
    @State private var commandResponse: String?
    @State private var logs: [PluginLogEntry] = []
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var isSaving = false

    var body: some View {
        SettingsSectionLayout(
            title: L10n.t("pluginsTitle", ns: "settings"),
            subtitle: L10n.t("pluginsDesc", ns: "settings")
        ) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("", selection: $workspaceTab) {
                        Text(L10n.t("installedTab", ns: "settings")).tag(PluginWorkspaceTab.installed)
                        Text(L10n.t("marketplaceTab", ns: "settings")).tag(PluginWorkspaceTab.marketplace)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if workspaceTab == .installed {
                        HStack(alignment: .top, spacing: 16) {
                            pluginList
                                .frame(width: 250)

                            Divider()

                            pluginDetail
                        }
                    } else {
                        marketplaceContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .task {
            await loadPlugins()
        }
        .task(id: workspaceTab) {
            if workspaceTab == .marketplace, !hasLoadedMarketplace {
                await loadMarketplace()
            }
        }
        .sheet(item: $pendingMarketplaceAction) { action in
            PluginInstallConfirmationView(pluginName: action.pluginName) {
                await performMarketplaceAction(action)
            }
        }
    }

    private var filteredMarketplaceEntries: [MarketplacePluginEntry] {
        let query = marketplaceSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !query.isEmpty else {
            return marketplaceEntries
        }

        return marketplaceEntries.filter { entry in
            let plugin = entry.plugin

            return plugin.name.localizedCaseInsensitiveContains(query)
                || plugin.description.localizedCaseInsensitiveContains(query)
                || plugin.author.localizedCaseInsensitiveContains(query)
                || (plugin.tags?.contains { $0.localizedCaseInsensitiveContains(query) } ?? false)
                || (plugin.categories?.contains { $0.localizedCaseInsensitiveContains(query) } ?? false)
        }
    }

    private var marketplaceContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("marketplaceTitle", ns: "settings"))
                        .font(.system(size: 14, weight: .semibold))

                    Text(L10n.t("marketplaceDesc", ns: "settings"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await loadMarketplace() }
                } label: {
                    Label(L10n.t("refreshBtn", ns: "settings"), systemImage: "arrow.clockwise")
                }
                .disabled(isMarketplaceLoading)
            }

            TextField(L10n.t("marketplaceSearchPlaceholder", ns: "settings"), text: $marketplaceSearch)
                .textFieldStyle(.roundedBorder)

            if isMarketplaceLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let marketplaceError {
                VStack(spacing: 10) {
                    Text(marketplaceError)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Button(L10n.t("marketplaceRetry", ns: "settings")) {
                        Task { await loadMarketplace() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredMarketplaceEntries.isEmpty {
                Text(L10n.t("marketplaceNoResults", ns: "settings"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredMarketplaceEntries) { entry in
                            let installedPlugin = plugins.first { $0.pluginId == entry.plugin.id }

                            PluginMarketplaceCard(
                                entry: entry,
                                isInstalled: installedPlugin != nil,
                                installedVersion: installedPlugin?.version
                            ) { version, isUpdate in
                                pendingMarketplaceAction = PendingMarketplaceAction(
                                    pluginId: entry.plugin.id,
                                    pluginName: entry.plugin.name,
                                    version: version.version,
                                    isUpdate: isUpdate
                                )
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var pluginList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: L10n.t("installedTab", ns: "settings"))

                Spacer()

                Button {
                    Task { await loadPlugins() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help(L10n.t("refreshBtn", ns: "settings"))
                .accessibilityLabel(L10n.t("refreshBtn", ns: "settings"))
            }

            if plugins.isEmpty, errorMessage == nil {
                Text(L10n.t("noPluginsTitle", ns: "settings"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ForEach(plugins) { plugin in
                HStack(spacing: 4) {
                    Button {
                        Task { await inspect(plugin) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: plugin.enabled ? "puzzlepiece.fill" : "puzzlepiece")
                                .foregroundStyle(plugin.enabled ? Theme.accent : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(plugin.name ?? plugin.pluginId)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .lineLimit(1)

                                Text("v\(plugin.version ?? "?") · sdk \(plugin.sdkVersion)")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            if plugin.loadError != nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(8)
                        .background(
                            selected?.pluginId == plugin.pluginId ? Theme.elevated : .clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button(plugin.enabled ? L10n.t("pluginDisabled", ns: "settings") : L10n.t("pluginEnabled", ns: "settings")) {
                            Task { await toggle(plugin) }
                        }

                        Button(L10n.t("removePluginTitle", ns: "settings"), role: .destructive) {
                            Task { await remove(plugin) }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 24, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel(plugin.name ?? plugin.pluginId)
                }
                .contextMenu {
                    Button(plugin.enabled ? L10n.t("pluginDisabled", ns: "settings") : L10n.t("pluginEnabled", ns: "settings")) {
                        Task { await toggle(plugin) }
                    }

                    Button(L10n.t("removePluginTitle", ns: "settings"), role: .destructive) {
                        Task { await remove(plugin) }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var pluginDetail: some View {
        if let selected {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selected.name ?? selected.pluginId)
                            .font(.title3.bold())

                        Text(selected.pluginId)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle(
                        L10n.t(selected.enabled ? "pluginEnabled" : "pluginDisabled", ns: "settings"),
                        isOn: Binding(
                            get: { selected.enabled },
                            set: { enabled in
                                Task { await setEnabled(enabled, for: selected) }
                            }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel(L10n.t(selected.enabled ? "pluginEnabled" : "pluginDisabled", ns: "settings"))
                }

                if let description = selected.description {
                    Text(description)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                if let loadError = selected.loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                Picker("", selection: $detailTab) {
                    ForEach(PluginDetailTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.green)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ScrollView {
                    tabContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text(L10n.t("pluginSelectPrompt", ns: "macos"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch detailTab {
        case .settings:
            settingsContent
        case .permissions:
            permissionsContent
        case .commands:
            commandsContent
        case .logs:
            logsContent
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        if let selected, let settings {
            if settings.definitions.isEmpty {
                Text(L10n.t("pluginNoSettings", ns: "macos"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(settings.definitions, id: \.key) { definition in
                        PluginSettingField(
                            definition: definition,
                            value: settingBinding(for: definition),
                            isSecretSet: secretKeys.contains(definition.key)
                        )
                    }

                    Button(L10n.t("saveChanges", ns: "settings")) {
                        Task { await saveSettings(for: selected) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }
            }
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var permissionsContent: some View {
        if capabilities.isEmpty {
            Text(L10n.t("pluginNoPermissions", ns: "macos"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(capabilities, id: \.self) { capability in
                    capabilityRow(capability)
                }
            }
        }
    }

    private func capabilityRow(_ capability: PluginCapability) -> some View {
        let access = capabilityAccess(for: capability)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(capability.name)
                    .font(.system(size: 11.5, weight: .medium))

                Text(capability.type)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                if capabilityIsConfigured(capability) {
                    Button(L10n.t("pluginAccessResetToDefault", ns: "settings")) {
                        Task { await resetCapability(capability) }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                    .disabled(isSaving)
                }
            }

            if let description = capability.description {
                Text(description)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            if let requirement = capability.requires {
                Text(L10n.t("pluginAccessRequires", ns: "settings", ["permission": requirement]))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Picker(L10n.t("pluginAccessAudienceTitle", ns: "settings"), selection: Binding(
                get: { access.mode },
                set: { mode in
                    Task { await updateCapability(capability, mode: mode, roleIds: access.roleIds) }
                }
            )) {
                Text(L10n.t("pluginModePublic", ns: "macos")).tag("public")
                Text(L10n.t("pluginModeRestricted", ns: "macos")).tag("restricted")
            }
            .pickerStyle(.segmented)
            .disabled(isSaving)

            if access.mode == "restricted" {
                if session.roles.isEmpty {
                    Text(L10n.t("pluginNoRoles", ns: "macos"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.roles) { role in
                        Toggle(role.name, isOn: Binding(
                            get: { access.roleIds.contains(role.id) },
                            set: { selected in
                                var roleIds = access.roleIds

                                if selected {
                                    roleIds.append(role.id)
                                } else {
                                    roleIds.removeAll { $0 == role.id }
                                }

                                Task { await updateCapability(capability, mode: access.mode, roleIds: roleIds) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10.5))
                        .disabled(isSaving)
                    }
                }
            }

            Divider()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var commandsContent: some View {
        if commands.isEmpty {
            Text(L10n.t("pluginNoCommands", ns: "macos"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Picker(L10n.t("commandsTitle", ns: "settings"), selection: $selectedCommandId) {
                    ForEach(commands) { command in
                        Text("/\(command.name)").tag(command.id)
                    }
                }

                if let command = commands.first(where: { $0.id == selectedCommandId }) {
                    if let description = command.description {
                        Text(description)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(command.args ?? [], id: \.name) { argument in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(argument.name)
                                    .font(.system(size: 10.5, weight: .medium))

                                if let description = argument.description {
                                    Text(description)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            commandArgumentField(argument)
                                .frame(maxWidth: 220)
                        }
                    }

                    Button(L10n.t("pluginRunCommand", ns: "macos")) {
                        Task { await run(command) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }

                if let commandResponse {
                    Eyebrow(text: L10n.t("responseLabel", ns: "settings"))
                    Text(commandResponse)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .onChange(of: selectedCommandId) { _, _ in
                commandArguments = [:]
                commandResponse = nil
            }
        }
    }

    @ViewBuilder
    private func commandArgumentField(_ argument: PluginCommandArg) -> some View {
        if argument.type == "boolean" {
            Toggle(argument.name, isOn: Binding(
                get: { commandArguments[argument.name] == "true" },
                set: { commandArguments[argument.name] = $0 ? "true" : "false" }
            ))
            .labelsHidden()
        } else if argument.sensitive == true {
            SecureField(
                L10n.t("argValuePlaceholder", ns: "settings", ["name": argument.name]),
                text: argumentBinding(for: argument)
            )
            .textFieldStyle(.roundedBorder)
        } else {
            TextField(
                L10n.t("argValuePlaceholder", ns: "settings", ["name": argument.name]),
                text: argumentBinding(for: argument)
            )
            .textFieldStyle(.roundedBorder)
        }
    }

    private var logsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if logs.isEmpty {
                Text(L10n.t("noLogsYet", ns: "settings"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ForEach(logs) { log in
                HStack(alignment: .top, spacing: 8) {
                    Text(log.type)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text(log.message)
                        .font(.system(size: 10.5))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func settingBinding(for definition: PluginSettingDefinition) -> Binding<JSONValue> {
        Binding(
            get: {
                if definition.type == "secret" {
                    return settingValues[definition.key] ?? .string("")
                }

                return settingValues[definition.key] ?? definition.defaultValue ?? .null
            },
            set: { settingValues[definition.key] = $0 }
        )
    }

    private func argumentBinding(for argument: PluginCommandArg) -> Binding<String> {
        Binding(
            get: { commandArguments[argument.name] ?? "" },
            set: { commandArguments[argument.name] = $0 }
        )
    }

    private func capabilityKey(_ capability: PluginCapability) -> String {
        "\(capability.type):\(capability.name)"
    }

    private func capabilityAccess(for capability: PluginCapability) -> PluginCapabilitySelection {
        capabilityValues[capabilityKey(capability)] ?? PluginCapabilitySelection(
            mode: capability.mode ?? capability.defaultAccess?.mode ?? "public",
            roleIds: capability.roleIds ?? capability.defaultAccess?.roleIds ?? []
        )
    }

    private func capabilityIsConfigured(_ capability: PluginCapability) -> Bool {
        capability.configured || capabilityValues[capabilityKey(capability)] != nil
    }

    private func loadPlugins() async {
        do {
            plugins = try await session.getPlugins()
            errorMessage = nil
        } catch {
            errorMessage = SharkordSession.describe(error)
        }
    }

    private func loadMarketplace() async {
        isMarketplaceLoading = true
        marketplaceError = nil

        do {
            marketplaceEntries = try await PluginMarketplaceCatalog.fetch()
            hasLoadedMarketplace = true
        } catch {
            marketplaceError = L10n.t("marketplaceFetchError", ns: "settings")
        }

        isMarketplaceLoading = false
    }

    private func performMarketplaceAction(_ action: PendingMarketplaceAction) async -> String? {
        do {
            if action.isUpdate {
                try await session.updatePlugin(pluginId: action.pluginId, version: action.version)
            } else {
                try await session.installPlugin(pluginId: action.pluginId, version: action.version)
            }

            await loadPlugins()

            if let installed = plugins.first(where: { $0.pluginId == action.pluginId }) {
                await inspect(installed)
            }

            statusMessage = action.isUpdate
                ? L10n.t("pluginMarketplaceUpdateComplete", ns: "macos", ["name": action.pluginName])
                : L10n.t("pluginMarketplaceInstallComplete", ns: "macos", ["name": action.pluginName])

            return nil
        } catch {
            let key = action.isUpdate ? "marketplaceUpdateError" : "marketplaceInstallError"
            return "\(L10n.t(key, ns: "settings")): \(SharkordSession.describe(error))"
        }
    }

    private func inspect(_ plugin: PluginInfo) async {
        selected = plugin
        detailTab = .settings
        settings = nil
        settingValues = [:]
        secretKeys = []
        logs = []
        capabilities = []
        commands = []
        capabilityValues = [:]
        selectedCommandId = ""
        statusMessage = nil
        errorMessage = nil

        do {
            let loadedSettings = try await session.getPluginSettings(pluginId: plugin.pluginId)
            settings = loadedSettings
            settingValues = loadedSettings.values
            secretKeys = Set(loadedSettings.secretsSet ?? [])
            logs = try await session.getPluginLogs(pluginId: plugin.pluginId)
            capabilities = try await session.getPluginCapabilities(pluginId: plugin.pluginId)
            commands = try await session.getPluginCommands(pluginId: plugin.pluginId)
                .entries[plugin.pluginId] ?? []
            capabilityValues = [:]
            selectedCommandId = commands.first?.id ?? ""
        } catch {
            errorMessage = SharkordSession.describe(error)
        }
    }

    private func setEnabled(_ enabled: Bool, for plugin: PluginInfo) async {
        do {
            try await session.togglePlugin(pluginId: plugin.pluginId, enabled: enabled)
            await reload(pluginId: plugin.pluginId)
        } catch {
            errorMessage = SharkordSession.describe(error)
        }
    }

    private func toggle(_ plugin: PluginInfo) async {
        await setEnabled(!plugin.enabled, for: plugin)
    }

    private func remove(_ plugin: PluginInfo) async {
        do {
            try await session.removePlugin(pluginId: plugin.pluginId)
            if selected?.pluginId == plugin.pluginId {
                selected = nil
            }
            await loadPlugins()
        } catch {
            errorMessage = SharkordSession.describe(error)
        }
    }

    private func reload(pluginId: String) async {
        await loadPlugins()

        if let updated = plugins.first(where: { $0.pluginId == pluginId }) {
            selected = updated
        }
    }

    private func saveSettings(for plugin: PluginInfo) async {
        guard let settings else { return }
        isSaving = true
        errorMessage = nil
        statusMessage = nil

        do {
            for definition in settings.definitions {
                let value = settingValues[definition.key] ?? definition.defaultValue ?? .null
                let original = settings.values[definition.key] ?? definition.defaultValue ?? .null

                if definition.type == "secret" {
                    guard case .string(let secret) = value, !secret.isEmpty else { continue }
                } else if value == original {
                    continue
                }

                try await session.updatePluginSetting(pluginId: plugin.pluginId, key: definition.key, value: value)
            }

            let updatedSettings = try await session.getPluginSettings(pluginId: plugin.pluginId)
            self.settings = updatedSettings
            settingValues = updatedSettings.values
            secretKeys = Set(updatedSettings.secretsSet ?? [])
            statusMessage = L10n.t("pluginSettingsSaved", ns: "settings")
        } catch {
            errorMessage = SharkordSession.describe(error)
        }

        isSaving = false
    }

    private func updateCapability(_ capability: PluginCapability, mode: String, roleIds: [Int]) async {
        guard let selected else { return }
        isSaving = true
        errorMessage = nil

        do {
            try await session.setPluginCapabilityAccess(
                pluginId: selected.pluginId,
                type: capability.type,
                name: capability.name,
                mode: mode,
                roleIds: Array(Set(roleIds)).sorted()
            )
            capabilityValues[capabilityKey(capability)] = PluginCapabilitySelection(
                mode: mode,
                roleIds: Array(Set(roleIds)).sorted()
            )
            statusMessage = L10n.t("pluginCapabilitySaved", ns: "macos")
        } catch {
            errorMessage = SharkordSession.describe(error)
        }

        isSaving = false
    }

    private func resetCapability(_ capability: PluginCapability) async {
        guard let selected else { return }
        isSaving = true
        errorMessage = nil

        do {
            try await session.resetPluginCapabilityAccess(
                pluginId: selected.pluginId,
                type: capability.type,
                name: capability.name
            )
            capabilityValues.removeValue(forKey: capabilityKey(capability))
            capabilities = try await session.getPluginCapabilities(pluginId: selected.pluginId)
            statusMessage = L10n.t("pluginCapabilitySaved", ns: "macos")
        } catch {
            errorMessage = SharkordSession.describe(error)
        }

        isSaving = false
    }

    private func run(_ command: PluginCommand) async {
        guard let selected else { return }
        var args: [String: JSONValue] = [:]

        for argument in command.args ?? [] {
            let rawValue = commandArguments[argument.name] ?? ""

            if rawValue.isEmpty, argument.required == true, argument.type != "boolean" {
                errorMessage = L10n.t("pluginRequiredArgument", ns: "macos", ["name": argument.name])
                return
            }

            if rawValue.isEmpty {
                if argument.type == "boolean", argument.required == true {
                    args[argument.name] = .bool(false)
                }

                continue
            }

            switch argument.type {
            case "boolean":
                args[argument.name] = .bool(rawValue == "true")
            case "number":
                if let intValue = Int(rawValue) {
                    args[argument.name] = .int(intValue)
                } else if let doubleValue = Double(rawValue) {
                    args[argument.name] = .double(doubleValue)
                } else {
                    errorMessage = L10n.t("pluginInvalidNumber", ns: "macos", ["name": argument.name])
                    return
                }
            default:
                args[argument.name] = .string(rawValue)
            }
        }

        isSaving = true
        errorMessage = nil
        commandResponse = nil

        do {
            let result = try await session.executePluginCommand(
                pluginId: selected.pluginId,
                commandName: command.name,
                args: args,
                channelId: session.selectedChannelId
            )
            let data = try JSONEncoder().encode(result)
            commandResponse = String(data: data, encoding: .utf8) ?? String(describing: result)
        } catch {
            errorMessage = SharkordSession.describe(error)
        }

        isSaving = false
    }
}

private struct PluginSettingField: View {
    let definition: PluginSettingDefinition
    @Binding var value: JSONValue
    let isSecretSet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(definition.name)
                .font(.system(size: 11.5, weight: .medium))

            if let description = definition.description {
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            settingControl
        }
    }

    @ViewBuilder
    private var settingControl: some View {
        switch definition.type {
        case "boolean":
            Toggle(definition.name, isOn: Binding(
                get: { value.boolValue ?? false },
                set: { value = .bool($0) }
            ))
            .labelsHidden()
        case "number":
            TextField(definition.name, text: Binding(
                get: { numberText },
                set: { updateNumber($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 220)
        case "secret":
            SecureField(
                L10n.t(isSecretSet ? "secretSetPlaceholder" : "secretUnsetPlaceholder", ns: "settings"),
                text: Binding(
                    get: { value.stringValue ?? "" },
                    set: { value = .string($0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 320)
        case "enum":
            Picker(definition.name, selection: Binding(
                get: { value.stringValue ?? "" },
                set: { value = .string($0) }
            )) {
                ForEach(definition.options ?? [], id: \.label) { option in
                    Text(option.label).tag(option.value?.stringValue ?? option.label)
                }
            }
            .frame(maxWidth: 260)
        default:
            TextField(definition.name, text: Binding(
                get: { value.stringValue ?? "" },
                set: { value = .string($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)
        }
    }

    private var numberText: String {
        switch value {
        case .int(let number):
            return String(number)
        case .double(let number):
            return String(number)
        default:
            return ""
        }
    }

    private func updateNumber(_ text: String) {
        if let intValue = Int(text) {
            value = .int(intValue)
        } else if let doubleValue = Double(text) {
            value = .double(doubleValue)
        } else if text.isEmpty {
            value = .int(0)
        }
    }
}
