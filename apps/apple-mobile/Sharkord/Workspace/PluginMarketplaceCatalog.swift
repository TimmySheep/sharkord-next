import Foundation

struct MobileMarketplacePlugin: Decodable, Sendable {
    let id: String
    let name: String
    let description: String
    let author: String
    let logo: String
    let homepage: String?
    let tags: [String]?
    let categories: [String]?
    let verified: Bool
}

struct MobileMarketplacePluginVersion: Decodable, Identifiable, Sendable {
    var id: String { version }

    let version: String
    let downloadUrl: String
    let checksum: String
    let sdkVersion: Int
    let size: Double
    let timestamp: Double
}

struct MobileMarketplacePluginEntry: Decodable, Identifiable, Sendable {
    var id: String { plugin.id }

    let plugin: MobileMarketplacePlugin
    let versions: [MobileMarketplacePluginVersion]
}

enum MobileMarketplaceVersionOrder {
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
        case (.some, nil), (nil, nil):
            return false
        case (.some(let candidateParts), .some(let installedParts)):
            for (candidatePart, installedPart) in zip(candidateParts, installedParts) {
                if candidatePart == installedPart { continue }
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
        if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
        value = value.split(separator: "+", maxSplits: 1).first.map(String.init) ?? value
        let parts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".")
        guard (1...3).contains(numbers.count) else { return nil }

        var parsedNumbers: [Int] = []
        for component in numbers {
            guard let number = Int(component), number >= 0 else { return nil }
            parsedNumbers.append(number)
        }
        while parsedNumbers.count < 3 { parsedNumbers.append(0) }

        var prerelease: [String]?
        if parts.count == 2 {
            let identifiers = parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard identifiers.allSatisfy({
                !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
            }) else {
                return nil
            }
            prerelease = identifiers
        }
        return Version(numbers: parsedNumbers, prerelease: prerelease)
    }
}

enum MobilePluginMarketplaceCatalog {
    static let sdkVersion = 2
    private static let registryURL = URL(string: "https://raw.githubusercontent.com/Sharkord/plugins/refs/heads/main/plugins.json?raw=true")

    static func fetch() async throws -> [MobileMarketplacePluginEntry] {
        guard let registryURL else { throw URLError(.badURL) }
        var request = URLRequest(url: registryURL)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> [MobileMarketplacePluginEntry] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw URLError(.cannotParseResponse)
        }
        let decoder = JSONDecoder()
        return rows.compactMap { row in
            guard JSONSerialization.isValidJSONObject(row),
                  let rowData = try? JSONSerialization.data(withJSONObject: row),
                  let entry = try? decoder.decode(MobileMarketplacePluginEntry.self, from: rowData),
                  isValid(entry)
            else {
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
            return MobileMarketplacePluginEntry(plugin: entry.plugin, versions: versions)
        }
        .sorted { ($0.versions.first?.timestamp ?? 0) > ($1.versions.first?.timestamp ?? 0) }
    }

    static func compatibleVersion(in entry: MobileMarketplacePluginEntry) -> MobileMarketplacePluginVersion? {
        entry.versions
            .filter { $0.sdkVersion == sdkVersion }
            .reduce(nil) { current, next in
                guard let current else { return next }
                return MobileMarketplaceVersionOrder.isNewer(next.version, than: current.version) ? next : current
            }
    }

    private static func isValid(_ entry: MobileMarketplacePluginEntry) -> Bool {
        let plugin = entry.plugin
        return !plugin.id.isEmpty
            && plugin.id.count <= 64
            && plugin.id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
            && !plugin.name.isEmpty
            && isHTTPS(plugin.logo)
            && (plugin.homepage.map(isHTTP) ?? true)
            && entry.versions.allSatisfy { $0.size.isFinite && $0.timestamp.isFinite }
    }

    private static func isHTTPS(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return url.scheme?.lowercased() == "https" && url.host != nil
    }

    private static func isHTTP(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
    }
}
