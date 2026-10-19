import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct SelectedAccountIconsProjectionTests {
    @Test
    func `missing account usage never borrows active provider data and last known remains stale`() {
        let settings = testSettingsStore(suiteName: "Selected-projection", userDefaults: InMemoryUserDefaults())
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 37, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date(timeIntervalSince1970: 100))
        store.snapshots[.claude] = snapshot
        store.claudeSwapAccountSnapshots = [
            .init(
                id: .init(source: "claude-swap", opaqueID: "1"),
                provider: .claude,
                displayLabel: "First",
                isActive: true,
                usesLastKnownUsage: true,
                snapshot: snapshot,
                error: nil,
                sourceLabel: nil),
            .init(
                id: .init(source: "claude-swap", opaqueID: "2"),
                provider: .claude,
                displayLabel: "Second",
                isActive: false,
                snapshot: nil,
                error: nil,
                sourceLabel: nil),
        ]
        let inventory = store.selectedAccountIconInventory(for: .claude)
        #expect(inventory.count == 2)
        #expect(inventory[0].usesLastKnownUsage)
        #expect(inventory[0].isStale)
        #expect(inventory[1].snapshot == nil)
        #expect(inventory[1].isStale)
        let missingData = store.selectedAccountIconRenderData(
            input: inventory[1], provider: .claude, label: "Account 2", now: Date())
        #expect(missingData.primary == nil)
        #expect(missingData.session == nil)
        #expect(missingData.costToday == nil)
        #expect(missingData.balance == nil)
        #expect(missingData.weeklyPace == nil)
        #expect(missingData.iconKey == inventory[1].key.autosaveName)
        let focus = inventory[1].key
        #expect(store.selectedAccountIconMenuInputs(focused: focus).first?.key == focus)
        #expect(store.claudeSwapAccountSnapshots.first?.isActive == true)
        #expect(settings.selectedTokenAccount(for: .claude)?.id == nil)
    }

    @Test
    func `managed UUID inventory excludes profiles and rejects another workspace cache`() {
        let settings = testSettingsStore(suiteName: "Selected-managed", userDefaults: InMemoryUserDefaults())
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        let id = UUID()
        let managed = CodexVisibleAccount(
            id: "visible-fixture",
            email: "fixture@example.invalid",
            workspaceAccountID: "workspace-a",
            storedAccountID: id,
            selectionSource: .managedAccount(id: id),
            isActive: false,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let otherWorkspace = CodexVisibleAccount(
            id: managed.id,
            email: managed.email,
            workspaceAccountID: "workspace-b",
            storedAccountID: id,
            selectionSource: managed.selectionSource,
            isActive: false,
            isLive: false,
            canReauthenticate: true,
            canRemove: true)
        let profile = CodexVisibleAccount(
            id: "profile-fixture",
            email: "profile@example.invalid",
            storedAccountID: nil,
            selectionSource: .profileHome(path: "/synthetic/profile"),
            isActive: false,
            isLive: false,
            canReauthenticate: false,
            canRemove: false)
        settings.cachedCodexAccountMenuProjection = .init(
            activeSource: settings.codexPersistedActiveSource,
            loadedAt: Date(),
            projection: .init(
                visibleAccounts: [managed, profile],
                activeVisibleAccountID: nil,
                liveVisibleAccountID: nil,
                hasUnreadableAddedAccountStore: false))
        store.codexAccountSnapshots = [.init(
            account: otherWorkspace,
            snapshot: UsageSnapshot(primary: nil, secondary: nil, updatedAt: Date()),
            error: nil,
            sourceLabel: nil)]
        let inventory = store.selectedAccountIconInventory(for: .codex)
        #expect(inventory.count == 1)
        #expect(inventory.first?.key.opaqueID == id.uuidString)
        #expect(inventory.first?.snapshot == nil)
    }

    @Test
    func `token identity uses saved UUID and uncached accounts stay empty`() {
        let settings = testSettingsStore(suiteName: "Selected-token", userDefaults: InMemoryUserDefaults())
        settings.addTokenAccount(provider: .openrouter, label: "Fixture", token: "synthetic-token")
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        let inventory = store.selectedAccountIconInventory(for: .openrouter)
        #expect(inventory.count == 1)
        #expect(inventory.first?.key.source == "token-account")
        #expect(inventory.first?.key.opaqueID == settings.tokenAccounts(for: .openrouter).first?.id.uuidString)
        #expect(inventory.first?.snapshot == nil)
    }

    @Test
    func `selected demand and followed account precede other consumers within six slots`() {
        let admitted = UsageStore.admittingSelectedIconAccounts(
            Array(1...12), selectedIDs: [12, 11, 10, 9], followedID: 8, id: { $0 })
        #expect(admitted == [12, 11, 10, 9, 8, 1])
        #expect(UsageStore.admittingSelectedIconAccounts(
            [1], selectedIDs: [1], followedID: 1, id: { $0 }) == [1])
    }
}
