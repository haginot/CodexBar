import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct SelectedAccountIconsLifecycleTests {
    private final class Item: StatusItemConfiguring {
        var autosaveName: String!
        var length: CGFloat
        var button: NSStatusBarButton? {
            nil
        }

        init(length: CGFloat) { self.length = length }
    }

    @Test
    func `reorder retains items and teardown removes all accounts`() {
        let first = SelectedAccountIconKey(provider: "claude", source: "claude-swap", opaqueID: "1")
        let second = SelectedAccountIconKey(provider: "claude", source: "claude-swap", opaqueID: "2")
        let added = StatusItemController.accountStatusItemChanges(existing: [], desired: [first, second])
        #expect(added.create == [first, second])
        let reordered = StatusItemController.accountStatusItemChanges(
            existing: [first, second],
            desired: [second, first])
        #expect(reordered.create.isEmpty)
        #expect(reordered.remove.isEmpty)
        let shutdown = StatusItemController.accountStatusItemChanges(existing: [first, second], desired: [])
        #expect(shutdown.remove == [first, second])
        #expect(shutdown.create.isEmpty)
    }

    @Test
    func `account factory names and registers zero width items before callbacks can reenter`() {
        let key = SelectedAccountIconKey(provider: "codex", source: "codex-managed", opaqueID: "fixture-id")
        var registry: [SelectedAccountIconKey: Item] = [:]
        let item = StatusItemController.makeStatusItem(
            create: { Item(length: $0) },
            identity: .account(provider: key.provider, source: key.source, opaqueID: key.opaqueID),
            defaults: InMemoryUserDefaults(),
            legacyDefaultItemIndex: nil,
            onCreated: { item in
                registry[key] = item
                #expect(registry[key] === item)
                #expect(item.autosaveName == key.autosaveName)
                #expect(item.length == 0)
                item.length = 54
            })
        #expect(item.length == 54)
        #expect(item.autosaveName == key.autosaveName)
        #expect(StatusItemController.StatusItemIdentity.provider(.codex).autosaveName == "codexbar-codex")
    }
}
