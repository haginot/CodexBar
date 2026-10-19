import CodexBarCore
import Foundation

extension UsageStore {
    static let tokenAccountMenuSnapshotLimit = 6

    func freshCodexVisibleAccountsForSnapshotHydration() -> [CodexVisibleAccount] {
        self.freshCodexVisibleAccountProjectionForAccountRefresh().visibleAccounts
    }

    func tokenAccounts(for provider: UsageProvider) -> [ProviderTokenAccount] {
        guard TokenAccountSupportCatalog.support(for: provider) != nil else { return [] }
        return self.settings.tokenAccounts(for: provider)
    }

    func shouldFetchAllTokenAccounts(provider: UsageProvider, accounts: [ProviderTokenAccount]) -> Bool {
        guard TokenAccountSupportCatalog.support(for: provider) != nil else { return false }
        guard self.settings.effectiveSelectedTokenAccount(for: provider) != nil else { return false }
        return self.settings.selectedAccountIconKeys(for: provider).contains { key in
            key.source == "token-account" && accounts.contains { $0.id.uuidString == key.opaqueID }
        } || self.settings.accountWidgetsEnabled && !accounts.isEmpty
            || self.settings.multiAccountMenuLayout == .stacked && accounts.count > 1
    }

    func shouldFetchAllCodexVisibleAccounts() -> Bool {
        // PAT is not a per-visible-account credential. Fan-out would fetch the same token for
        // every row and then reject its whoami identity against other accounts.
        guard !self.shouldUseAmbientCodexPATForUsage() else { return false }
        let projection = self.freshCodexVisibleAccountProjectionForAccountRefresh()
        if !self.settings.selectedAccountIconKeys(for: .codex).isEmpty { return !projection.visibleAccounts.isEmpty }
        return (self.settings.multiAccountMenuLayout == .stacked || self.settings.accountWidgetsEnabled)
            && projection.visibleAccounts.count > 1
    }
}

extension UsageStore {
    /// Selected icons and the followed account have first claim on the existing six slots.
    /// Remaining consumers retain their relative order. Empty demand uses the legacy path unchanged.
    static func admittingSelectedIconAccounts<Account, ID: Hashable>(
        _ accounts: [Account], selectedIDs: [ID], followedID: ID?, id: (Account) -> ID) -> [Account]
    {
        var result: [Account] = []
        var seen = Set<ID>()
        let priority = selectedIDs + (followedID.map { [$0] } ?? [])
        for accountID in priority {
            if let account = accounts.first(where: { id($0) == accountID }), seen.insert(accountID).inserted {
                result.append(account)
            }
        }
        for account in accounts where seen.insert(id(account)).inserted {
            result.append(account)
        }
        return Array(result.prefix(Self.tokenAccountMenuSnapshotLimit))
    }
}

extension UsageStore {
    func limitedTokenAccounts(
        _ accounts: [ProviderTokenAccount],
        selected: ProviderTokenAccount?,
        provider: UsageProvider? = nil) -> [ProviderTokenAccount]
    {
        let iconKeys = (provider.map { self.settings.selectedAccountIconKeys(for: $0) } ?? [])
            .filter { $0.source == "token-account" }
        if !iconKeys.isEmpty {
            return Self.admittingSelectedIconAccounts(
                accounts,
                selectedIDs: iconKeys.compactMap { UUID(uuidString: $0.opaqueID) },
                followedID: selected?.id,
                id: { $0.id })
        }
        let limit = Self.tokenAccountMenuSnapshotLimit
        if accounts.count <= limit {
            return accounts
        }
        var limited = Array(accounts.prefix(limit))
        if let selected, !limited.contains(where: { $0.id == selected.id }) {
            limited.removeLast()
            limited.append(selected)
        }
        return limited
    }

    func limitedCodexVisibleAccounts(
        _ accounts: [CodexVisibleAccount],
        snapshots: [CodexAccountUsageSnapshot] = [],
        activeVisibleAccountID: String?) -> [CodexVisibleAccount]
    {
        let accounts = CodexAccountPresentationOrdering.orderedAccounts(
            accounts,
            snapshots: snapshots,
            activeVisibleAccountID: activeVisibleAccountID)
        let iconKeys = self.settings.selectedAccountIconKeys(for: .codex)
        if !iconKeys.isEmpty {
            let priorityIDs = iconKeys.compactMap { key in
                accounts.first { account in
                    guard case let .managedAccount(id) = account.selectionSource else { return false }
                    return key.source == "codex-managed" && id.uuidString == key.opaqueID
                }?.id
            }
            return Self.admittingSelectedIconAccounts(
                accounts, selectedIDs: priorityIDs, followedID: activeVisibleAccountID, id: { $0.id })
        }
        let limit = Self.tokenAccountMenuSnapshotLimit
        if accounts.count <= limit {
            return accounts
        }
        var limited = Array(accounts.prefix(limit))
        if let activeVisibleAccountID,
           let active = accounts.first(where: { $0.id == activeVisibleAccountID }),
           !limited.contains(where: { $0.id == activeVisibleAccountID })
        {
            limited.removeLast()
            limited.append(active)
        }
        return limited
    }

    func admitsCodexAccountRefresh(accounts: [CodexVisibleAccount], requestedAccountIDs: Set<String>?) -> Bool {
        if requestedAccountIDs != nil || !self.settings.selectedAccountIconKeys(for: .codex).isEmpty {
            return !accounts.isEmpty
        }
        return accounts.count > 1
    }
}
