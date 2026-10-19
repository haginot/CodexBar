import AppKit
import CodexBarCore

extension StatusItemController {
    func focusedAccountIdentity(for menu: NSMenu) -> ProviderAccountIdentity? {
        self.accountMenuFocus[ObjectIdentifier(menu)].map {
            ProviderAccountIdentity(source: $0.source, opaqueID: $0.opaqueID)
        }
    }

    func menuProvider(for menu: NSMenu) -> UsageProvider? {
        if self.shouldMergeIcons {
            return self.resolvedMenuProvider()
        }
        if let provider = self.menuProviders[ObjectIdentifier(menu)] {
            return provider.firstPartyProvider
        }
        if menu === self.fallbackMenu {
            return nil
        }
        return self.store.enabledFirstPartyProvidersForDisplay().first ?? .codex
    }

    func addSelectedAccountIconMenuCards(
        to menu: NSMenu, context: MenuCardContext, captureMenu: NSMenu?) -> Bool
    {
        let key = self.accountMenuFocus[ObjectIdentifier(captureMenu ?? menu)] ?? context.focusedAccount.map {
            SelectedAccountIconKey(provider: context.currentProvider.rawValue, source: $0.source, opaqueID: $0.opaqueID)
        }
        if let key {
            let ordered = self.store.selectedAccountIconMenuInputs(focused: key)
            let selected = self.settings.selectedAccountIcons.providers[key.provider]?.accounts ?? []
            let cards = ordered.enumerated().map { index, input in
                let ordinal = (selected.firstIndex(of: input.key) ?? (selected.count + index)) + 1
                let label = input.label(hidePersonalInfo: self.settings.hidePersonalInfo, ordinal: ordinal)
                return self.store.menuCardModel(for: context.currentProvider, context: .account(.init(
                    snapshot: input.snapshot,
                    error: input.error,
                    info: AccountInfo(email: label, plan: nil),
                    privacyOrdinal: .init(ordinal),
                    historySelection: .unavailable,
                    lastKnownUsageCapturedAt: input.usesLastKnownUsage ? input.snapshot?.updatedAt : nil,
                    label: label)))
            }
            if !cards.isEmpty { self.addStackedMenuCards(cards, to: menu, context: context) }
            return true
        }
        return false
    }
}
