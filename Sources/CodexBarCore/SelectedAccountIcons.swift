#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Saved presentation intent for one provider.
public enum ProviderStatusItemMode: String, Codable, Sendable {
    case providerIcon
    case selectedAccounts
}

/// Credential-free identity supplied by an account source. Never construct from an email or token.
public struct SelectedAccountIconKey: Hashable, Codable, Sendable {
    /// Provider raw value or instance identifier.
    public let provider: String
    /// Source namespace, such as `codex-managed` or `claude-swap`.
    public let source: String
    /// Stable source-owned opaque identifier.
    public let opaqueID: String

    /// Creates an identity without consulting account or credential stores.
    public init(provider: String, source: String, opaqueID: String) {
        self.provider = provider
        self.source = source
        self.opaqueID = opaqueID
    }

    /// Stable placement name; display aliases and opaque IDs never appear in plaintext.
    public var autosaveName: String {
        let material = [self.provider, self.source, self.opaqueID].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(material.utf8)).prefix(8)
            .map { String(format: "%02x", $0) }.joined()
        return "codexbar-\(self.provider)-acct-\(digest)"
    }

    /// Stable accessibility identifier, distinct from the privacy-filtered spoken label.
    public var accessibilityIdentifier: String { self.autosaveName }
}

// MARK: - Persistence

/// Local, additive settings. Unsupported versions are immutable and retain their entire payload.
public struct SelectedAccountIconsSettings: Codable, Sendable {
    /// Supported schema version.
    public static let currentVersion = 1
    /// Maximum saved selection per provider.
    public static let maximumAccounts = 4

    /// Payload schema version.
    public private(set) var version: Int
    /// Normalized supported entries; empty for unsupported schemas.
    public private(set) var providers: [String: Entry]
    private var futurePayload: JSONValue?
    private var originalData: Data?

    /// Saved mode and ordered opaque account identities.
    public struct Entry: Codable, Equatable, Sendable {
        /// Saved presentation mode.
        public var mode: ProviderStatusItemMode
        /// Selected keys in user order.
        public var accounts: [SelectedAccountIconKey]

        /// Creates an entry, normalized when installed in settings.
        public init(mode: ProviderStatusItemMode = .providerIcon, accounts: [SelectedAccountIconKey] = []) {
            self.mode = mode
            self.accounts = accounts
        }
    }

    /// Creates normalized settings for the supported schema.
    public init(providers: [String: Entry] = [:]) {
        self.version = Self.currentVersion
        self.providers = providers
        self.normalize()
    }

    /// Whether the payload belongs to a newer, unsupported schema.
    public var isReadOnly: Bool { self.version != Self.currentVersion }

    /// Updates saved intent, ignoring edits to unsupported payloads.
    public mutating func setEntry(_ entry: Entry?, for provider: String) {
        guard !self.isReadOnly else { return }
        self.providers[provider] = entry
        self.normalize()
    }

    /// Loads local JSON, falling back to defaults for malformed or missing data.
    public static func load(from data: Data?) -> Self {
        guard let data, var settings = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        if settings.isReadOnly { settings.originalData = data }
        return settings
    }

    /// Returns JSON for persistence, preserving unsupported input byte for byte when loaded from data.
    public func encodedData() throws -> Data {
        if let originalData = self.originalData { return originalData }
        return try JSONEncoder().encode(self)
    }

    private enum CodingKeys: String, CodingKey { case version, providers }

    public init(from decoder: any Decoder) throws {
        self.init()
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let version = try container.decode(Int.self, forKey: .version)
            guard version > 0 else { return }
            if version != Self.currentVersion {
                self.futurePayload = try JSONValue(from: decoder)
                self.version = version
                return
            }
            self.providers = try container.decode([String: Entry].self, forKey: .providers)
            self.normalize()
        } catch {
            self = Self()
        }
    }

    public func encode(to encoder: any Encoder) throws {
        if let futurePayload = self.futurePayload {
            try futurePayload.encode(to: encoder)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.version, forKey: .version)
        try container.encode(self.providers, forKey: .providers)
    }

    private mutating func normalize() {
        for (provider, entry) in self.providers {
            var seen = Set<SelectedAccountIconKey>()
            let accounts = entry.accounts.filter { $0.provider == provider && seen.insert($0).inserted }
            self.providers[provider] = Entry(mode: entry.mode, accounts: Array(accounts.prefix(Self.maximumAccounts)))
        }
    }
}

/// JSON structure for schemas whose fields this version cannot interpret.
private indirect enum JSONValue: Codable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Decimal), bool(Bool), null

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Decimal.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? value.decode([JSONValue].self) { self = .array(array) }
        else { self = try .object(value.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case let .object(object): try value.encode(object)
        case let .array(array): try value.encode(array)
        case let .string(string): try value.encode(string)
        case let .number(number): try value.encode(number)
        case let .bool(bool): try value.encode(bool)
        case .null: try value.encodeNil()
        }
    }
}

// MARK: - Planning and privacy

/// Pure selection policy; inventory contains resolvable identities, independently of usage availability.
public enum SelectedAccountIconsPlanner {
    /// One split status item. Ordinals are one-based positions in the saved normalized selection.
    public enum PlannedItem: Equatable, Sendable {
        case provider(String)
        case account(SelectedAccountIconKey, ordinal: Int)
    }

    /// Plans in provider order. Saved merge intent suppresses account expansion without changing settings.
    public static func plan(
        providers: [String],
        mergeIconsSaved: Bool,
        settings: SelectedAccountIconsSettings,
        inventory: [String: Set<SelectedAccountIconKey>]) -> [PlannedItem]
    {
        providers.flatMap { provider -> [PlannedItem] in
            guard !mergeIconsSaved, !settings.isReadOnly,
                  let entry = settings.providers[provider], entry.mode == .selectedAccounts
            else { return [.provider(provider)] }
            let accounts = entry.accounts.enumerated().compactMap { index, key -> PlannedItem? in
                guard inventory[provider]?.contains(key) == true else { return nil }
                return .account(key, ordinal: index + 1)
            }
            return accounts.isEmpty ? [.provider(provider)] : accounts
        }
    }
}

/// Shared display policy for badges, tooltips, and spoken accessibility labels.
public enum SelectedAccountIconsPrivacy {
    /// Maximum alias length in extended grapheme clusters.
    public static let maximumAliasLength = 16

    /// Uses an explicit alias only when privacy permits it. Email-like aliases are rejected before truncation.
    public static func label(
        for _: SelectedAccountIconKey,
        alias: String?,
        hidePersonalInfo: Bool,
        ordinal: Int) -> String
    {
        let fallback = "Account \(ordinal)"
        guard !hidePersonalInfo, let alias else { return fallback }
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("@"),
              !trimmed.unicodeScalars.contains(where: { $0.value < 32 || (127...159).contains($0.value) })
        else { return fallback }
        return String(trimmed.prefix(Self.maximumAliasLength))
    }
}
