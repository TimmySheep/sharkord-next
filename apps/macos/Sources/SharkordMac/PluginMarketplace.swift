import Foundation
import SharkordCore
import SwiftUI

struct MarketplacePlugin: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let author: String
    let logo: String
    let homepage: String?
    let tags: [String]?
    let categories: [String]?
    let verified: Bool
    let screenshots: [String]?
}

struct MarketplacePluginVersion: Decodable, Hashable, Identifiable, Sendable {
    var id: String { version }

    let version: String
    let downloadUrl: String
    let checksum: String
    let sdkVersion: Int
    let size: Double
    let timestamp: Double
}

struct MarketplacePluginEntry: Decodable, Identifiable, Sendable {
    var id: String { plugin.id }

    let plugin: MarketplacePlugin
    let versions: [MarketplacePluginVersion]
}

enum MarketplaceVersionOrder {
    private struct Version {
        let numbers: [Int]
        let prerelease: [String]?
    }

    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        guard let candidate = parse(candidate), let installed = parse(installed) else {
            return false
        }

        for index in 0..<3 where candidate.numbers[index] != installed.numbers[index] {
            return candidate.numbers[index] > installed.numbers[index]
        }

        switch (candidate.prerelease, installed.prerelease) {
        case (nil, .some):
            return true
        case (.some, nil):
            return false
        case (nil, nil):
            return false
        case (.some(let candidateParts), .some(let installedParts)):
            for (candidatePart, installedPart) in zip(candidateParts, installedParts) {
                if candidatePart == installedPart {
                    continue
                }

                switch (Int(candidatePart), Int(installedPart)) {
                case (.some(let candidateNumber), .some(let installedNumber)):
                    return candidateNumber > installedNumber
                case (.some, .none):
                    return false
                case (.none, .some):
                    return true
                case (.none, .none):
                    return candidatePart > installedPart
                }
            }

            return candidateParts.count > installedParts.count
        }
    }

    private static func parse(_ rawValue: String) -> Version? {
        var value = rawValue

        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }

        value = value.split(separator: "+", maxSplits: 1).first.map(String.init) ?? value
        let parts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".")

        guard (1...3).contains(numbers.count) else {
            return nil
        }

        var parsedNumbers: [Int] = []

        for component in numbers {
            guard let number = Int(component), number >= 0 else {
                return nil
            }

            parsedNumbers.append(number)
        }

        while parsedNumbers.count < 3 {
            parsedNumbers.append(0)
        }

        var prerelease: [String]?

        if parts.count == 2 {
            let identifiers = parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)

            guard identifiers.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }) else {
                return nil
            }

            prerelease = identifiers
        }

        return Version(numbers: parsedNumbers, prerelease: prerelease)
    }
}

enum PluginMarketplaceCatalog {
    static let sdkVersion = 2

    private static let registryURL = URL(string: "https://raw.githubusercontent.com/Sharkord/plugins/refs/heads/main/plugins.json?raw=true")

    static func fetch() async throws -> [MarketplacePluginEntry] {
        guard let registryURL else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: registryURL)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try decode(data)
    }

    static func decode(_ data: Data) throws -> [MarketplacePluginEntry] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw URLError(.cannotParseResponse)
        }

        let decoder = JSONDecoder()

        return rows.compactMap { row in
            guard JSONSerialization.isValidJSONObject(row),
                  let rowData = try? JSONSerialization.data(withJSONObject: row),
                  let entry = try? decoder.decode(MarketplacePluginEntry.self, from: rowData),
                  isValid(entry) else {
                return nil
            }

            let versions = entry.versions
                .filter {
                    !$0.version.isEmpty
                        && !$0.checksum.isEmpty
                        && $0.sdkVersion >= 0
                        && $0.size.isFinite
                        && $0.timestamp.isFinite
                        && isHTTPS($0.downloadUrl)
                }
                .sorted { $0.timestamp > $1.timestamp }

            return MarketplacePluginEntry(plugin: entry.plugin, versions: versions)
        }
        .sorted { ($0.versions.first?.timestamp ?? 0) > ($1.versions.first?.timestamp ?? 0) }
    }

    static func compatibleVersion(in entry: MarketplacePluginEntry) -> MarketplacePluginVersion? {
        entry.versions
            .filter { $0.sdkVersion == sdkVersion }
            .reduce(nil) { current, next in
                guard let current else {
                    return next
                }

                return MarketplaceVersionOrder.isNewer(next.version, than: current.version) ? next : current
            }
    }

    private static func isValid(_ entry: MarketplacePluginEntry) -> Bool {
        let plugin = entry.plugin

        return !plugin.id.isEmpty
            && plugin.id.count <= 64
            && plugin.id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
            && !plugin.name.isEmpty
            && isHTTPS(plugin.logo)
            && (plugin.homepage.map(isHTTP) ?? true)
            && (plugin.screenshots?.allSatisfy(isHTTPS) ?? true)
            && entry.versions.allSatisfy { $0.size.isFinite && $0.timestamp.isFinite }
    }

    private static func isHTTPS(_ value: String) -> Bool {
        guard let url = URL(string: value) else {
            return false
        }

        return url.scheme?.lowercased() == "https" && url.host != nil
    }

    private static func isHTTP(_ value: String) -> Bool {
        guard let url = URL(string: value) else {
            return false
        }

        return (url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https") && url.host != nil
    }
}

struct PluginMarketplaceCard: View {
    let entry: MarketplacePluginEntry
    let isInstalled: Bool
    let installedVersion: String?
    let onInstall: (MarketplacePluginVersion, Bool) -> Void

    private var compatibleVersion: MarketplacePluginVersion? {
        PluginMarketplaceCatalog.compatibleVersion(in: entry)
    }

    private var updateAvailable: Bool {
        guard let installedVersion, let compatibleVersion else {
            return false
        }

        return MarketplaceVersionOrder.isNewer(compatibleVersion.version, than: installedVersion)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            logo

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(entry.plugin.name)
                                .font(.system(size: 13, weight: .semibold))

                            if entry.plugin.verified {
                                Label(L10n.t("marketplaceVerified", ns: "settings"), systemImage: "checkmark.seal.fill")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(Theme.accent)
                                    .help(L10n.t("marketplaceVerifiedTooltip", ns: "settings"))
                            }
                        }

                        Text(entry.plugin.description)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 6)

                    actionButton
                }

                HStack(spacing: 10) {
                    Text(entry.plugin.author)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)

                    if let version = entry.versions.first {
                        Text("v\(version.version)")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Text(L10n.t(
                            "marketplaceReleasedOn",
                            ns: "settings",
                            ["date": releaseDate(version.timestamp)]
                        ))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                    }

                    if let homepage = entry.plugin.homepage, let url = URL(string: homepage) {
                        Link(homepage, destination: url)
                            .font(.system(size: 9.5))
                            .lineLimit(1)
                    }
                }

                if let compatibleVersion {
                    Label(
                        L10n.t("marketplaceSdkCompatibleTooltip", ns: "settings", ["version": compatibleVersion.sdkVersion]),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.system(size: 9.5))
                    .foregroundStyle(.green)
                } else {
                    Label(
                        L10n.t(
                            "marketplaceSdkIncompatibleTooltip",
                            ns: "settings",
                            ["required": entry.versions.first?.sdkVersion ?? "?", "current": PluginMarketplaceCatalog.sdkVersion]
                        ),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 9.5))
                    .foregroundStyle(.orange)
                }

                if let tags = entry.plugin.tags, !tags.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Theme.elevated, in: Capsule())
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                if let screenshots = entry.plugin.screenshots, !screenshots.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(screenshots, id: \.self) { screenshot in
                                if let url = URL(string: screenshot) {
                                    Link(destination: url) {
                                        AsyncImage(url: url) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Theme.elevated)
                                        }
                                        .frame(width: 120, height: 68)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    .accessibilityLabel(entry.plugin.name)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.elevated, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var logo: some View {
        if let url = URL(string: entry.plugin.logo) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "puzzlepiece.extension.fill")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.elevated)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .accessibilityLabel(entry.plugin.name)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if updateAvailable, let compatibleVersion {
            Button(L10n.t("marketplaceUpdateBtn", ns: "settings")) {
                onInstall(compatibleVersion, true)
            }
            .buttonStyle(.borderedProminent)
        } else if !isInstalled, let compatibleVersion {
            Button(L10n.t("marketplaceInstallBtn", ns: "settings")) {
                onInstall(compatibleVersion, false)
            }
            .buttonStyle(.borderedProminent)
        } else if isInstalled {
            Text(L10n.t("marketplaceInstalledBadge", ns: "settings"))
                .font(.system(size: 9.5, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.elevated, in: Capsule())
        }
    }

    private func releaseDate(_ timestamp: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.language)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date(timeIntervalSince1970: timestamp / 1000))
    }
}

struct PluginInstallConfirmationView: View {
    @Environment(\.dismiss) private var dismiss

    let pluginName: String
    let onConfirm: () async -> String?

    @State private var remainingSeconds = 3
    @State private var isInstalling = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("pluginInstallConfirmTitle", ns: "dialogs", ["name": pluginName]))
                .font(.title3.bold())

            Text(L10n.t("pluginInstallConfirmLead", ns: "dialogs"))
                .font(.system(size: 12))

            warningLine("pluginInstallWarningLine1", highlight: "pluginInstallWarningHighlight1")
            warningLine("pluginInstallWarningLine2", highlight: "pluginInstallWarningHighlight2")
            warningLine("pluginInstallWarningLine3", highlight: "pluginInstallWarningHighlight3")

            Text(L10n.t("pluginInstallUseDocker", ns: "dialogs"))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(L10n.t("cancel", ns: "dialogs")) {
                    dismiss()
                }

                Spacer()

                Button {
                    confirm()
                } label: {
                    if isInstalling {
                        ProgressView().controlSize(.small)
                    } else if remainingSeconds > 0 {
                        Text(L10n.t("pluginInstallConfirmCountdown", ns: "dialogs", ["seconds": remainingSeconds]))
                    } else {
                        Text(L10n.t("pluginInstallConfirmBtn", ns: "dialogs"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(remainingSeconds > 0 || isInstalling)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
        .task {
            for _ in 0..<3 {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }

                remainingSeconds -= 1
            }
        }
    }

    private func warningLine(_ lineKey: String, highlight highlightKey: String) -> some View {
        Label {
            (Text(L10n.t(lineKey, ns: "dialogs")) + Text(" ") + Text(L10n.t(highlightKey, ns: "dialogs")).bold())
                .font(.system(size: 11))
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func confirm() {
        guard remainingSeconds == 0, !isInstalling else {
            return
        }

        isInstalling = true
        errorMessage = nil

        Task {
            if let errorMessage = await onConfirm() {
                self.errorMessage = errorMessage
                isInstalling = false
            } else {
                dismiss()
            }
        }
    }
}
