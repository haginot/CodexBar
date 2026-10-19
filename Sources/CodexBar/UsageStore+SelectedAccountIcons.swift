import CodexBarCore
import Foundation

/// Retained inventory, independent of whether an account has ever fetched successfully.
struct SelectedAccountIconInput: Identifiable {
    let key: SelectedAccountIconKey
    let alias: String?
    let snapshot: UsageSnapshot?
    let error: String?
    let usesLastKnownUsage: Bool

    var id: SelectedAccountIconKey {
        self.key
    }

    var identity: ProviderAccountIdentity {
        .init(source: self.key.source, opaqueID: self.key.opaqueID)
    }

    var isStale: Bool {
        self.snapshot == nil || self.error != nil || self.usesLastKnownUsage
    }

    func label(hidePersonalInfo: Bool, ordinal: Int) -> String {
        SelectedAccountIconsPrivacy.label(
            for: self.key, alias: self.alias, hidePersonalInfo: hidePersonalInfo, ordinal: ordinal)
    }
}

extension UsageStore {
    func selectedAccountIconMenuInputs(focused key: SelectedAccountIconKey) -> [SelectedAccountIconInput] {
        guard let provider = UsageProvider(rawValue: key.provider) else { return [] }
        let inventory = self.selectedAccountIconInventory(for: provider)
        let focused = inventory.first { $0.key == key } ?? SelectedAccountIconInput(
            key: key, alias: nil, snapshot: nil, error: "Account unavailable", usesLastKnownUsage: false)
        return [focused] + inventory.filter { $0.key != key }
    }

    func selectedAccountIconInventory(for provider: UsageProvider) -> [SelectedAccountIconInput] {
        if provider == .claude, !self.claudeSwapAccountSnapshots.isEmpty {
            return self.claudeSwapAccountSnapshots.map {
                SelectedAccountIconInput(
                    key: .init(provider: provider.rawValue, source: $0.id.source, opaqueID: $0.id.opaqueID),
                    alias: $0.displayLabel,
                    snapshot: $0.snapshot,
                    error: $0.error,
                    usesLastKnownUsage: $0.usesLastKnownUsage)
            }
        }
        if provider == .codex {
            // Cached projection only: Settings/icon rendering must never discover credentials.
            let accounts = self.settings.codexVisibleAccountProjectionForMenuDisplay?.visibleAccounts ?? []
            return accounts.compactMap { account in
                guard case let .managedAccount(id) = account.selectionSource else { return nil }
                let cached = self.codexAccountSnapshots.first {
                    $0.id == account.id && Self.codexPriorSnapshotAccountMatches($0.account, account: account)
                }
                return SelectedAccountIconInput(
                    key: .init(provider: provider.rawValue, source: "codex-managed", opaqueID: id.uuidString),
                    alias: nil,
                    snapshot: cached?.snapshot,
                    error: cached?.error,
                    usesLastKnownUsage: false)
            }
        }
        guard self.settings.effectiveSelectedTokenAccount(for: provider) != nil else { return [] }
        let accounts = self.tokenAccounts(for: provider)
        let cached = self.validTokenAccountSnapshots(provider: provider, accounts: accounts)
        return accounts.map { account in
            let record = cached.first { $0.id == account.id }
            return SelectedAccountIconInput(
                key: .init(provider: provider.rawValue, source: "token-account", opaqueID: account.id.uuidString),
                alias: account.displayName,
                snapshot: record?.snapshot,
                error: record?.error,
                usesLastKnownUsage: false)
        }
    }

    func selectedAccountIconPlan(providers: [UsageProvider]) -> [SelectedAccountIconsPlanner.PlannedItem] {
        let inventory = Dictionary(uniqueKeysWithValues: providers.map {
            ($0.rawValue, Set(self.selectedAccountIconInventory(for: $0).map(\.key)))
        })
        return SelectedAccountIconsPlanner.plan(
            providers: providers.map(\.rawValue),
            mergeIconsSaved: self.settings.mergeIcons,
            settings: self.settings.selectedAccountIcons,
            inventory: inventory)
    }
}
