import CodexBarCore
import SwiftUI

@MainActor
struct PreferencesSelectedAccountIconsSection: View {
    let provider: UsageProvider
    @Bindable var store: UsageStore
    @Bindable var settings: SettingsStore

    private var entry: SelectedAccountIconsSettings.Entry {
        self.settings.selectedAccountIcons.providers[self.provider.rawValue] ?? .init()
    }

    private func save(_ entry: SelectedAccountIconsSettings.Entry) {
        var value = self.settings.selectedAccountIcons
        value.setEntry(entry, for: self.provider.rawValue)
        self.settings.selectedAccountIcons = value
    }

    var body: some View {
        Section("Menu bar accounts") {
            Picker("Menu bar", selection: Binding(
                get: { self.entry.mode },
                set: { self.save(.init(mode: $0, accounts: self.entry.accounts)) }))
            {
                Text("One provider icon").tag(ProviderStatusItemMode.providerIcon)
                Text("Selected account icons").tag(ProviderStatusItemMode.selectedAccounts)
            }
            .disabled(self.settings.mergeIcons || self.settings.selectedAccountIcons.isReadOnly)
            if self.settings.mergeIcons {
                Text("Selected account icons require Merge Icons to be off. Your selection is kept.")
                Button("Turn off Merge Icons") { self.settings.mergeIcons = false }
            }
            if self.settings.selectedAccountIcons.isReadOnly {
                Text("These settings were saved by a newer version of CodexBar and are read-only.")
            }
            if self.entry.mode == .selectedAccounts {
                let inventory = self.store.selectedAccountIconInventory(for: self.provider)
                ForEach(Array(inventory.enumerated()), id: \.element.id) { index, input in
                    Toggle(
                        input.label(
                            hidePersonalInfo: self.settings.hidePersonalInfo,
                            ordinal: (self.entry.accounts.firstIndex(of: input.key) ?? index) + 1),
                        isOn: Binding(
                            get: { self.entry.accounts.contains(input.key) },
                            set: { selected in
                                var entry = self.entry
                                entry.accounts.removeAll { $0 == input.key }
                                if selected { entry.accounts.append(input.key) }
                                self.save(entry)
                            }))
                            .disabled(self.settings.mergeIcons || self.settings.selectedAccountIcons.isReadOnly
                                || (!self.entry.accounts.contains(input.key)
                                    && self.entry.accounts.count >= SelectedAccountIconsSettings.maximumAccounts))
                }
                ForEach(self.entry.accounts.filter { key in
                    !inventory.contains { $0.key == key }
                }, id: \.self) { key in
                    Toggle("Selected account unavailable — selection retained", isOn: Binding(
                        get: { self.entry.accounts.contains(key) },
                        set: { selected in
                            guard !selected else { return }
                            var entry = self.entry
                            entry.accounts.removeAll { $0 == key }
                            self.save(entry)
                        }))
                        .disabled(self.settings.mergeIcons || self.settings.selectedAccountIcons.isReadOnly)
                }
                Text("Choose up to four accounts. If none are available, the provider icon is shown.")
                    .font(.caption)
                if self.provider == .codex {
                    let ineligible = self.settings.codexVisibleAccountProjectionForMenuDisplay?.visibleAccounts.filter {
                        if case .managedAccount = $0.selectionSource { return false }
                        return true
                    } ?? []
                    ForEach(Array(ineligible.enumerated()), id: \.element.id) { index, _ in
                        Toggle("Account \(index + 1) — profile/system account unavailable", isOn: .constant(false))
                            .disabled(true)
                    }
                    Text(
                        "Profile and system accounts are not eligible. Choose managed accounts.")
                        .font(.caption)
                }
            }
        }
    }
}
