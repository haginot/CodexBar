import CodexBarCore
import Foundation
import Observation
import Testing
@testable import CodexBar

private final class SelectedAccountIconsObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        self.lock.lock()
        self.value = true
        self.lock.unlock()
    }

    func get() -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.value
    }
}

@MainActor
struct SelectedAccountIconsSettingsTests {
    @Test
    func `local selection survives restart and saved merge keeps intent`() {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: "Selected-icons", userDefaults: defaults)
        let key = SelectedAccountIconKey(provider: "claude", source: "claude-swap", opaqueID: "2")
        let value = SelectedAccountIconsSettings(providers: [
            "claude": .init(mode: .selectedAccounts, accounts: [key]),
        ])
        let changed = SelectedAccountIconsObservationFlag()
        withObservationTracking {
            _ = settings.menuObservationToken
        } onChange: {
            changed.set()
        }
        settings.selectedAccountIcons = value
        #expect(changed.get())
        #expect(defaults.data(forKey: "selectedAccountIconsV1") != nil)
        settings.mergeIcons = true
        #expect(settings.selectedAccountIconKeys(for: .claude).isEmpty)
        #expect(settings.selectedAccountIcons.providers["claude"]?.accounts == [key])
        let restored = testSettingsStore(suiteName: "Selected-icons-reload", userDefaults: defaults)
        #expect(restored.selectedAccountIcons.providers["claude"]?.accounts == [key])
        restored.mergeIcons = false
        #expect(restored.selectedAccountIconKeys(for: .claude) == [key])
    }

    @Test
    func `future payload cannot be overwritten by app setters`() {
        let payload = Data(#"{"version":42,"future":{"keep":true}}"#.utf8)
        let defaults = InMemoryUserDefaults(values: ["selectedAccountIconsV1": payload])
        let settings = testSettingsStore(suiteName: "Selected-icons-future", userDefaults: defaults)
        #expect(settings.selectedAccountIcons.isReadOnly)
        settings.selectedAccountIcons = .init()
        #expect(defaults.data(forKey: "selectedAccountIconsV1") == payload)
        #expect(settings.selectedAccountIconKeys(for: .claude).isEmpty)
    }
}
