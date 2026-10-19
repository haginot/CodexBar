import AppKit
import CodexBarCore

extension StatusItemController {
    func selectedAccountIconObservationSignature() -> String {
        self.settings.orderedFirstPartyProviders().map { provider in
            let keys = self.settings.selectedAccountIconKeys(for: provider)
            guard !keys.isEmpty else { return "" }
            return self.store.selectedAccountIconInventory(for: provider).filter { keys.contains($0.key) }.map {
                "\($0.key.autosaveName):\(String(describing: $0.snapshot)):\($0.error ?? "")"
                    + ":\($0.usesLastKnownUsage):\($0.alias ?? "")"
            }.joined(separator: "|")
        }.joined(separator: "||")
    }

    func firstAccountStatusItem(for provider: UsageProvider) -> NSStatusItem? {
        self.settings.selectedAccountIconKeys(for: provider).compactMap { self.accountStatusItems[$0] }.first
    }

    func hasAccountStatusItems(for provider: UsageProvider) -> Bool {
        self.accountStatusItems.keys.contains { $0.provider == provider.rawValue }
    }

    @discardableResult
    func reconcileAccountStatusItems() -> Set<String> {
        let plan = self.shouldMergeIcons ? [] : self.store.selectedAccountIconPlan(
            providers: self.settings.orderedFirstPartyProviders().filter(self.isEnabled))
        let desired = plan.compactMap { item -> SelectedAccountIconKey? in
            if case let .account(key, _) = item { return key }
            return nil
        }
        let changes = Self.accountStatusItemChanges(existing: Set(self.accountStatusItems.keys), desired: desired)
        for key in changes.remove {
            self.removeAccountStatusItem(key)
        }
        for key in changes.create {
            guard let provider = UsageProvider(rawValue: key.provider) else { continue }
            let item = Self.makeStatusItem(
                create: self.statusBar.statusItem(withLength:),
                identity: .account(provider: key.provider, source: key.source, opaqueID: key.opaqueID),
                defaults: self.settings.userDefaults,
                legacyDefaultItemIndex: nil,
                onCreated: { self.accountStatusItems[key] = $0 })
            let menu = self.makeMenu(for: provider)
            self.accountMenus[key] = menu
            self.accountMenuFocus[ObjectIdentifier(menu)] = key
            item.menu = menu
        }
        for key in desired {
            if let item = self.accountStatusItems[key] {
                self.setStatusItemVisiblePreservingPlacement(item, true)
            }
        }
        return Set(desired.map(\.autosaveName))
    }

    func removeAccountStatusItem(_ key: SelectedAccountIconKey) {
        if let menu = self.accountMenus.removeValue(forKey: key) {
            menu.cancelTrackingWithoutAnimation()
            self.accountMenuFocus.removeValue(forKey: ObjectIdentifier(menu))
            self.removeMenuLifecycleState(ObjectIdentifier(menu))
            self.menuProviders.removeValue(forKey: ObjectIdentifier(menu))
        }
        guard let item = self.accountStatusItems.removeValue(forKey: key) else { return }
        item.menu = nil
        self.removeStatusItemPreservingPlacement(item)
    }

    static func accountStatusItemChanges(
        existing: Set<SelectedAccountIconKey>, desired: [SelectedAccountIconKey])
        -> (remove: Set<SelectedAccountIconKey>, create: [SelectedAccountIconKey])
    {
        (existing.subtracting(desired), desired.filter { !existing.contains($0) })
    }

    func removeAllAccountStatusItems() {
        for key in Self.accountStatusItemChanges(existing: Set(self.accountStatusItems.keys), desired: []).remove {
            self.removeAccountStatusItem(key)
        }
    }
}
