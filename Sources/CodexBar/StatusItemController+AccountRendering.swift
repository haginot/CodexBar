import AppKit
import CodexBarCore

extension StatusItemController {
    func renderAccountStatusItems(now: Date = .init()) {
        for (key, item) in self.accountStatusItems {
            guard let provider = UsageProvider(rawValue: key.provider), let button = item.button,
                  let input = self.store.selectedAccountIconInventory(for: provider).first(where: { $0.key == key })
            else { continue }
            let ordinal = (self.settings.selectedAccountIcons.providers[key.provider]?.accounts
                .firstIndex(of: key) ?? 0) + 1
            let label = input.label(hidePersonalInfo: self.settings.hidePersonalInfo, ordinal: ordinal)
            let data = self.store.selectedAccountIconRenderData(
                input: input,
                provider: provider,
                label: label,
                now: now)
            let resolution = self.settings.menuBarLayoutResolution(for: provider)
            var lines = resolution.layout.lines
            if !lines.isEmpty { lines[0].insert(contentsOf: [.accountLabel, .space], at: 0) }
            let options = MenuBarLayoutRenderOptions(
                size: self.settings.menuBarLayoutSize,
                highContrast: self.shouldUseHighContrastStatusItemContent,
                showUsed: self.settings.usageBarsShowUsed,
                conditionals: self.settings.menuBarLayoutConditionals,
                appearanceName: button.effectiveAppearance.name.rawValue,
                isDebugApp: Self.isDebugApp(bundleIdentifier: Bundle.main.bundleIdentifier),
                isStale: input.isStale,
                isHighlighted: button.isHighlighted,
                now: now,
                verticalAdjustment: self.settings.menuBarLayoutVerticalAdjustment,
                colorByProvider: self.settings.menuBarColorByProvider,
                monospacedDigits: self.settings.menuBarLayoutMonospacedDigits,
                showWindowLabels: self.settings.menuBarLayoutShowWindowLabels)
            let rendered = self.menuBarLayoutRenderer.render(
                layout: MenuBarLayout(lines: lines),
                data: data,
                icon: self.accountStatusItemIcon(input: input, provider: provider),
                options: options)
            item.length = Self.applyMenuBarLayoutContent(rendered, for: button, gap: self.settings.menuBarLayoutGap)
            button.toolTip = label + (input.isStale ? " — Unavailable or stale" : "")
            button.setAccessibilityTitle(button.toolTip)
        }
    }

    private func accountStatusItemIcon(input: SelectedAccountIconInput, provider: UsageProvider) -> NSImage? {
        if self.settings.menuBarShowsBrandIconWithPercent { return ProviderBrandIcon.image(for: provider) }
        let style = self.store.style(for: provider)
        let percents = input.snapshot.map {
            IconRemainingResolver.resolvedPercents(
                snapshot: $0,
                style: style,
                showUsed: self.settings.usageBarsShowUsed,
                secondaryOverrideWindowID: self.settings.copilotIconSecondaryWindowOverrideID(snapshot: $0))
        }
        return IconRenderer.makeIcon(
            primaryRemaining: percents?.primary,
            weeklyRemaining: percents?.secondary,
            creditsRemaining: nil,
            stale: input.isStale,
            style: style,
            hideCritters: self.settings.menuBarHidesCritters,
            quotaLayoutPolicy: .provider(provider, snapshot: input.snapshot))
    }

    func selectedAccountIconTiming(now: Date) -> (countdown: [Date], absolute: [Date], delays: [TimeInterval]) {
        var result: (countdown: [Date], absolute: [Date], delays: [TimeInterval]) = ([], [], [])
        for key in self.accountStatusItems.keys {
            guard let provider = UsageProvider(rawValue: key.provider),
                  let input = self.store.selectedAccountIconInventory(for: provider).first(where: { $0.key == key })
            else { continue }
            let data = self.store.selectedAccountIconRenderData(input: input, provider: provider, label: "", now: now)
            let layout = self.settings.menuBarLayoutResolution(for: provider).layout
            for token in layout.flattenedTokens(conditionals: self.settings.menuBarLayoutConditionals) {
                let window: MenuBarLayoutRenderWindow? = switch token.resetWindow {
                case .session: data.session
                case .weekly: data.weekly
                case .automatic: data.automatic
                case .scopedWeekly: data.scopedWeekly
                case .spend: data.spend
                case nil: nil
                }
                guard let date = window?.resetsAt else { continue }
                if token.resetIsAbsolute { result.absolute.append(date) }
                else { result.countdown.append(date) }
            }
            let predicates = layout.referencedConditionalPredicates(
                conditionals: self.settings.menuBarLayoutConditionals)
            for predicate in predicates {
                let window: MenuBarLayoutRenderWindow? = switch predicate.metric {
                case .sessionResetsIn: data.session
                case .weeklyResetsIn: data.weekly
                case .scopedWeeklyResetsIn: data.scopedWeekly
                case .automaticResetsIn: data.automatic
                default: nil
                }
                guard let date = window?.resetsAt else { continue }
                let delay = date.addingTimeInterval(-predicate.threshold * 3600).timeIntervalSince(now)
                if delay > 0 { result.delays.append(delay + 0.05) }
            }
        }
        return result
    }
}
