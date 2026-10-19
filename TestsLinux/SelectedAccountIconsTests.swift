import CodexBarCore
import Foundation
import Testing

struct SelectedAccountIconsTests {
    private func key(_ id: String, provider: String = "codex", source: String = "codex-managed")
        -> SelectedAccountIconKey
    {
        SelectedAccountIconKey(provider: provider, source: source, opaqueID: id)
    }

    @Test
    func `normalization deduplicates preserves order caps and drops mismatched providers`() throws {
        let keys = (1...6).map { self.key(String($0)) }
        let settings = SelectedAccountIconsSettings(providers: [
            "codex": .init(mode: .selectedAccounts, accounts: [
                self.key("wrong", provider: "claude"), keys[2], keys[0], keys[2],
                keys[4], keys[1], keys[3], keys[5],
            ]),
        ])
        let expected = [keys[2], keys[0], keys[4], keys[1]]
        #expect(settings.providers["codex"]?.accounts == expected)
        let decoded = try JSONDecoder().decode(SelectedAccountIconsSettings.self, from: settings.encodedData())
        #expect(decoded.providers == settings.providers)
        #expect(decoded.version == 1)
        #expect(!decoded.isReadOnly)
        var edited = settings
        edited.setEntry(.init(accounts: keys + keys), for: "codex")
        #expect(edited.providers["codex"]?.accounts == Array(keys.prefix(4)))
        edited.setEntry(nil, for: "codex")
        #expect(edited.providers.isEmpty)
    }

    @Test
    func `planner replaces providers in order with stable saved ordinals and falls back`() {
        let first = self.key("1")
        let second = self.key("2")
        let third = self.key("3")
        let settings = SelectedAccountIconsSettings(providers: [
            "codex": .init(mode: .selectedAccounts, accounts: [first, second, third]),
            "claude": .init(mode: .selectedAccounts, accounts: [self.key("1", provider: "claude")]),
        ])
        let inventory: [String: Set<SelectedAccountIconKey>] = ["codex": [third, second]]
        #expect(SelectedAccountIconsPlanner.plan(
            providers: ["other", "codex", "claude"], mergeIconsSaved: false,
            settings: settings, inventory: inventory) == [
            .provider("other"), .account(second, ordinal: 2), .account(third, ordinal: 3), .provider("claude"),
        ])
        for merge in [false, true] {
            #expect(SelectedAccountIconsPlanner.plan(
                providers: ["codex"], mergeIconsSaved: merge, settings: settings,
                inventory: merge ? inventory : [:]) == [.provider("codex")])
        }
        #expect(settings.providers["codex"]?.accounts == [first, second, third])
        #expect(SelectedAccountIconsPlanner.plan(
            providers: ["codex"], mergeIconsSaved: false,
            settings: .init(providers: ["codex": .init(accounts: [second])]),
            inventory: inventory) == [.provider("codex")])
        #expect(SelectedAccountIconsPlanner.plan(
            providers: [], mergeIconsSaved: false, settings: settings, inventory: inventory).isEmpty)
    }

    @Test
    func `saved merge wins even with only one provider and selection restores afterward`() {
        let key = self.key("1")
        let settings = SelectedAccountIconsSettings(providers: [
            "codex": .init(mode: .selectedAccounts, accounts: [key]),
        ])
        for merge in [true, false] {
            let expected: [SelectedAccountIconsPlanner.PlannedItem] = merge
                ? [.provider("codex")] : [.account(key, ordinal: 1)]
            #expect(SelectedAccountIconsPlanner.plan(
                providers: ["codex"], mergeIconsSaved: merge,
                settings: settings, inventory: ["codex": [key]]) == expected)
        }
    }

    @Test(arguments: [nil, "", " \n ", "person@example.com", "Team <person@example.com>",
                      "long-alias-before-the-email@example.com", "Team\nPrivate"] as [String?])
    func `unsafe or empty aliases use ordinal without exposing identity`(alias: String?) {
        #expect(SelectedAccountIconsPrivacy.label(
            for: self.key("person@example.com"), alias: alias, hidePersonalInfo: false, ordinal: 3) == "Account 3")
    }

    @Test
    func `privacy wins and aliases are trimmed and bounded by characters`() {
        let key = self.key("1")
        #expect(SelectedAccountIconsPrivacy.label(
            for: key, alias: " Work ", hidePersonalInfo: false, ordinal: 2) == "Work")
        #expect(SelectedAccountIconsPrivacy.label(
            for: key, alias: "Work", hidePersonalInfo: true, ordinal: 2) == "Account 2")
        let alias = String(repeating: "👩‍💻", count: 30)
        #expect(SelectedAccountIconsPrivacy.label(
            for: key, alias: alias, hidePersonalInfo: false, ordinal: 1)
            == String(alias.prefix(SelectedAccountIconsPrivacy.maximumAliasLength)))
    }

    @Test
    func `names hash the namespaced tuple and never expose account text`() {
        let key = self.key("fixture-id")
        #expect(key.autosaveName == "codexbar-codex-acct-8a99062e46cbe7c6")
        #expect(key.accessibilityIdentifier == key.autosaveName)
        #expect(key.autosaveName == self.key("fixture-id").autosaveName)
        #expect(key.autosaveName != self.key("fixture-id", source: "token-account").autosaveName)
        #expect(key.autosaveName != self.key("fixture-id", provider: "claude").autosaveName)
        #expect(key.autosaveName != self.key("other").autosaveName)
        let privateKey = self.key("person@example.com/private/path")
        #expect(!privateKey.autosaveName.contains("person"))
        #expect(!privateKey.autosaveName.contains("@"))
        #expect(!privateKey.autosaveName.contains("/"))
        #expect(privateKey.autosaveName.count == "codexbar-codex-acct-".count + 16)
    }

    @Test
    func `future schemas preserve unknown fields read only and plan provider items`() throws {
        let json = #"{ "version": 99, "providers": {"codex": "future-mode"}, "extra": [null,true,1.25,"x"] }"#
        let data = Data(json.utf8)
        var settings = SelectedAccountIconsSettings.load(from: data)
        #expect(settings.version == 99)
        #expect(settings.isReadOnly)
        #expect(settings.providers.isEmpty)
        settings.setEntry(.init(mode: .selectedAccounts, accounts: [self.key("1")]), for: "codex")
        #expect(try settings.encodedData() == data)
        let roundTrip = try JSONEncoder().encode(settings)
        let expected = try JSONSerialization.jsonObject(with: data) as? NSDictionary
        #expect(try JSONSerialization.jsonObject(with: roundTrip) as? NSDictionary == expected)
        #expect(SelectedAccountIconsPlanner.plan(
            providers: ["codex"], mergeIconsSaved: false, settings: settings,
            inventory: ["codex": [self.key("1")]]) == [.provider("codex")])
    }

    @Test(arguments: ["", "null", "[]", "{}", "{", #"{"version":0,"providers":{}}"#,
                      #"{"version":"1","providers":{}}"#, #"{"version":1}"#,
                      #"{"version":1,"providers":{"codex":{"mode":"unknown","accounts":[]}}}"#,
                      #"{"version":1,"providers":{"codex":{"mode":"selectedAccounts","accounts":[{}]}}}"#])
    func `malformed payloads fall back to defaults`(json: String) {
        let settings = SelectedAccountIconsSettings.load(from: Data(json.utf8))
        #expect(settings.version == 1)
        #expect(settings.providers.isEmpty)
        #expect(!settings.isReadOnly)
        #expect(SelectedAccountIconsSettings.load(from: nil).providers.isEmpty)
    }
}
