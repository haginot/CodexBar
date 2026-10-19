import CodexBarCore
import Foundation

extension SettingsStore {
    var selectedAccountIcons: SelectedAccountIconsSettings {
        get { self.defaultsState.selectedAccountIcons }
        set {
            guard !self.defaultsState.selectedAccountIcons.isReadOnly,
                  let data = try? newValue.encodedData() else { return }
            self.defaultsState.selectedAccountIcons = newValue
            self.userDefaults.set(data, forKey: "selectedAccountIconsV1")
        }
    }

    func selectedAccountIconKeys(for provider: UsageProvider) -> [SelectedAccountIconKey] {
        guard !self.mergeIcons, !self.selectedAccountIcons.isReadOnly,
              let entry = self.selectedAccountIcons.providers[provider.rawValue],
              entry.mode == .selectedAccounts else { return [] }
        return entry.accounts
    }
}
