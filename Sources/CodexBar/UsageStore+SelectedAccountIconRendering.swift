import CodexBarCore
import Foundation

extension UsageStore {
    /// Resolve semantic windows directly from the account snapshot. Provider credits, costs and history
    /// deliberately never enter this projection, including when the snapshot is missing.
    func selectedAccountIconRenderData(
        input: SelectedAccountIconInput, provider: UsageProvider, label: String, now: Date)
        -> MenuBarLayoutRenderData
    {
        let snapshot = input.snapshot
        let semantic = MenuBarLayoutSemanticWindowResolver.windows(provider: provider, snapshot: snapshot)
        let automatic = MenuBarMetricWindowResolver.rateWindow(
            preference: .automatic,
            provider: provider,
            snapshot: snapshot,
            supportsAverage: self.settings.menuBarMetricSupportsAverage(for: provider),
            antigravityPrioritizeExhaustedQuotas: self.settings.antigravityPrioritizeExhaustedQuotas,
            now: now)
        let scoped = MenuBarLayoutSemanticWindowResolver.scopedWeeklyNamedWindow(snapshot: snapshot)
        return MenuBarLayoutRenderData(
            provider: provider,
            iconKey: input.key.autosaveName,
            providerName: L(self.metadata(for: provider).displayName),
            accountLabel: label,
            laneLabels: MenuBarLayoutLaneLabels(provider: provider, snapshot: snapshot),
            primary: MenuBarLayoutRenderWindow(snapshot?.primary),
            secondary: MenuBarLayoutRenderWindow(snapshot?.secondary),
            tertiary: MenuBarLayoutRenderWindow(snapshot?.tertiary),
            extraRateWindows: (snapshot?.extraRateWindows ?? []).map(MenuBarLayoutRenderExtra.init),
            session: MenuBarLayoutRenderWindow(semantic.session),
            weekly: MenuBarLayoutRenderWindow(semantic.weekly),
            scopedWeekly: MenuBarLayoutRenderWindow(scoped?.window),
            scopedWeeklyTitle: scoped?.title,
            automatic: MenuBarLayoutRenderWindow(automatic),
            automaticText: nil,
            sessionPace: nil,
            weeklyPace: nil,
            automaticPace: nil,
            runsOut: nil,
            balance: nil,
            costToday: nil,
            cost30d: nil,
            metrics: .unavailable)
    }
}
