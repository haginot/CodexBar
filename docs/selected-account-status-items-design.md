---
summary: "Proposal: opt-in Selected account icons — show up to four accounts of one provider as separate menu bar items, simultaneously."
read_when:
  - Implementing or reviewing per-account menu bar status items
  - Deciding data sources for multi-account display
---

# Selected account icons (per-account menu bar items) — design proposal

Status: **Proposal (fork `haginot/CodexBar`, branch `multi-account-simultaneous`). Not reviewed by maintainers.**

Builds on the accepted decisions in [claude-multi-account-and-status-items.md](claude-multi-account-and-status-items.md)
and the code map in [multi-account-status-items-codemap.md](multi-account-status-items-codemap.md).
Related: #1268 and #1959 (folded into #1843), #1756, #1843 follow-ups (2026-10-08, 2026-10-18), closed PRs #3251 and #3881.

## 1. Problem

Users with two or more subscriptions of the same provider (for example two ChatGPT/Codex plans and two Claude plans)
want to watch every account's session and weekly windows **at a glance, at the same time**, without opening the menu
and without switching the active account.

```
[Codex · A  12% / 40%]  [Codex · B  71% / 88%]  [Claude · 1  5% / 22%]  [Claude · 2  64% / 30%]
```

## 2. Upstream state (2026-10-19, `main` @ 8fa003e)

Already shipped — this proposal does **not** change any of it:

- **Account sources**: Codex managed accounts and configured profile homes (`CODEX_HOME` scoped); Claude opt-in
  read-only `claude-swap` adapter (`cswap --list --json`) with explicit switching; labeled token accounts (OpenRouter,
  Kimi, Doubao, ClinePass, …).
- **In-menu display**: Stacked/Segmented account cards; "Show all accounts in Overview".
- **Model**: `ProviderAccountIdentity` / `ProviderAccountUsageSnapshot` in `CodexBarCore` (produced today by the
  claude-swap adapter only).

Not shipped: separate per-account menu bar items. The accepted direction (claude-multi-account doc, "Per-account
status item behavior") is **Selected account icons**: opt-in per provider, at most four, replaces that provider's
item, mutually exclusive with Merge Icons, stable `StatusItemIdentity.account(provider:source:opaqueID:)`,
alias/ordinal labels. The closures of #3251 and #3881 add concrete requirements, which this design adopts verbatim:

| Requirement (from closure notes) | How this design satisfies it |
| --- | --- |
| Capped selection (4), replaces provider item, disabled with Merge Icons | §4.1, §4.4 |
| Provider-neutral account projection | §4.2 (bridge Codex + token snapshots into `ProviderAccountUsageSnapshot`-shaped inputs) |
| Current zero-width / name-before-registration factory | §4.3 (reuse `makeStatusItem`, register before callbacks) |
| Placement preservation; no bypass of saved custom layouts | §4.3, §4.5 (account items render through `MenuBarLayoutRenderer` + the provider's resolved layout) |
| Account-scoped layout/menu data, provider-aware windows | §4.5, §4.6 |
| Explicit unavailable/stale behavior | §4.5 |
| Bounded refresh demand; no uncapped refresh when the option is off | §4.7 |
| Downgrade-safe persistence | §4.8 |

## 3. Non-goals

- No new credential source, Keychain enumeration, OAuth vault, or `CLAUDE_CONFIG_DIR` credential reads (see #1829 closure).
- No automatic switching, session launching, account add/import/export.
- No new usage endpoint. No change to the Claude OAuth → CLI → Web chain or Codex OAuth/CLI-RPC chain.
- No change for users who do not opt in (identical items, autosave names, positions, refresh demand).

## 4. Proposed architecture

### 4.1 Settings model (Core, Linux-testable)

`Sources/CodexBarCore/SelectedAccountIcons.swift` (new):

```swift
public enum ProviderStatusItemMode: String, Codable, Sendable { case providerIcon, selectedAccounts }

public struct SelectedAccountIconKey: Hashable, Codable, Sendable {   // persisted, opaque only
    public let provider: String          // UsageProvider raw value / ProviderInstanceID
    public let source: String            // "claude-swap", "codex-managed", "token-account", ...
    public let opaqueID: String          // slot number, managed UUID, token-account UUID
}

public struct SelectedAccountIconsSettings: Codable, Sendable {
    public var version: Int              // 1
    public var providers: [String: Entry] // provider -> mode + ordered keys
    public struct Entry: Codable, Sendable { var mode: ProviderStatusItemMode; var accounts: [SelectedAccountIconKey] }
}
```

- Normalization: dedupe, preserve user order, cap at **4**, drop keys whose provider mismatches the entry.
- Pure planner: `SelectedAccountIconsPlanner.plan(providers:mergeIconsSaved:settings:inventory:) -> [PlannedItem]`
  where `PlannedItem` is `.provider(id)` or `.account(key, ordinal)`. Rules: Merge Icons saved → no account items;
  provider in `selectedAccounts` mode with ≥1 resolvable selected account → its account items replace the provider
  item, in saved order; zero resolvable → fall back to the provider item (and Settings shows why).
- Privacy label policy: `label(for:alias:hidePersonalInfo:ordinal:)` → user alias (bounded length) or `Account N`;
  never email; Hide Personal Info always wins (title, tooltip, accessibility).
- Autosave name: `codexbar-<provider>-acct-<digest>` where digest = first 16 hex of SHA-256 over the namespaced
  tuple `provider\u{1F}source\u{1F}opaqueID`. Existing `codexbar-merged` / `codexbar-<provider>` names are unchanged.

### 4.2 Account inventory projection (app)

`UsageStore+SelectedAccountIcons.swift` (new) projects existing inventories into one list per provider:

| Source | Eligible key | Notes |
| --- | --- | --- |
| Claude `claude-swap` | `claude-swap` + slot | Existing `ProviderAccountUsageSnapshot`. Last-known (`usesLastKnownUsage`) is shown as stale, never as live. |
| Codex managed accounts | `codex-managed` + managed UUID | Ownership/workspace validated on lookup. |
| Codex profile homes / system | *phase 2* | Needs an opaque local registry (current visible IDs may contain emails/paths). Shown as ineligible with an explanation in phase 1. |
| Token accounts | `token-account` + UUID | Never token or label derived. |

No fetcher or credential code changes. Missing usage stays missing — never borrowed from the active account.

### 4.3 Status item lifecycle (AppKit)

- `StatusItemIdentity.account(provider:source:opaqueID:)` added; created through the existing
  `makeStatusItem` zero-width → autosave name → register → variable length factory.
- Identity-keyed registry `accountStatusItems: [AccountItemID: NSStatusItem]`, with its own menus.
- `updateVisibility`, `attachMenus`, reorder, removal, recovery, expected-visible names and shutdown are driven from
  the planner output so the replaced provider item cannot be recreated by `attachMenus`.
- Placement preserved via `MenuBarStatusItemPlacementPreflight` / `preservingPreferredPosition`; provider and account
  positions are kept independently, so turning the mode off restores the provider item at its old position.

### 4.4 Settings UI

Provider detail → Accounts → **Menu bar**: `One provider icon` (default) / `Selected account icons`, followed by up to
four checkboxes from the inventory (unavailable accounts listed but disabled with reason), and an alias/ordinal
preview. While Merge Icons is on, controls are disabled with a **Turn off Merge Icons** button; the saved selection is
kept so turning Merge Icons off restores it.

### 4.5 Rendering

Account items reuse `MenuBarLayoutRenderer` with the provider's resolved layout (provider override → global → legacy)
and `MenuBarMetricWindowResolver` with that provider's semantics — no new image path, no Session/Weekly substitution.
Inputs are account-owned only: snapshot, error, stale, reset times. Provider-scoped extras that cannot be attributed
to the account (cost, credits for another account, pace history) are omitted. A leading short badge (alias or ordinal)
distinguishes items. Unavailable → `–` with stale styling and a tooltip; last-known → stale styling with age in the
menu. Render caches/animation/countdown keys include the item identity.

### 4.6 Menu

Each account item owns an `NSMenu` whose context carries a focused `ProviderAccountIdentity`. Opening it shows that
account's card first (the provider's other accounts follow as today) and **never** changes the followed/active
account, token selection, Codex source, or Claude credentials. Explicit activation stays on the existing actions.

### 4.7 Refresh demand

No new timer. Selected account icons add demand to the existing fan-out policy (`UsageStore+AccountRefreshPolicy`):
selected keys (≤4) + the followed account are admitted first within the existing six-account cap; the
`accounts.count > 1` early exit does not suppress a single selected inactive account. With the option off, demand is
byte-for-byte today's. Manual refresh mode, disabled providers, PAT exclusion and claude-swap's single bounded list
read are respected.

### 4.8 Persistence / migration

New additive local defaults key `selectedAccountIconsV1` (JSON). Not in `config.json`, not synced. Older app versions
ignore it and keep their provider items; unknown future versions are read-only and fall back to provider items. No
migration of existing keys; provider autosave positions untouched.

## 5. Data-source choice and Terms of Service

This feature is **display-only** and consumes whatever source the user already configured. It adds no endpoint.

- **Codex (recommended)**: per account `CODEX_HOME` and the CLI RPC source (`codex app-server`,
  `account/rateLimits/read`) — the first-party Codex surface. Managed accounts already scope `CODEX_HOME`.
- **Claude**: the only upstream multi-account source is the opt-in `claude-swap` adapter. claude-swap (like CodexBar's
  OAuth source) reads `api.anthropic.com/api/oauth/usage` with the user's OAuth token; some users consider this a
  Consumer-Terms grey area (Claude Code legal note on OAuth use outside Claude Code; see jarrodwatts/claude-hud#287).
  The documented first-party alternative is Claude Code's statusLine JSON (`rate_limits.five_hour` / `seven_day`),
  per `CLAUDE_CONFIG_DIR`, which was approved as opt-in (#2733) and then reverted (#3006) for narrow benefit. This
  proposal deliberately does not revive it; it only notes that the account-icon layer is source-neutral, so any
  future source that produces `ProviderAccountUsageSnapshot` works unchanged.

## 6. Testing

- Linux (`TestsLinux/SelectedAccountIconsTests.swift`): normalization (dedupe/order/cap), planner (merge exclusivity,
  replacement, zero-resolvable fallback, ordinals), privacy labels, autosave-name stability and no-PII, Codable
  round-trip, unknown version passthrough, malformed payloads.
- macOS focused: settings state, inventory projection (no borrowed data, stale/last-known), refresh admission within the
  six cap, status item reconciliation with fake `StatusItemConfiguring`, menu focus without activation, shutdown.
- `make check`; `make test-fast FILTER='SelectedAccountIcons|StatusItemCreationOrdering|StatusItemControllerSplitLifecycle'`;
  synthetic packaged proof with fake accounts only (no Keychain prompts, no live probes).

## 7. Open questions for maintainers

1. Is a contributor PR welcome for this, or do you prefer a maintainer implementation (closure notes of #3251/#3881)?
   If welcome, would you accept it as a stack: (a) Core policy + tests, (b) inventory projection + refresh admission,
   (c) AppKit items + settings UI?
2. Codex profile homes / system account: OK to exclude in phase 1, or should an opaque local ID registry land first?
3. Alias: source-provided only (claude-swap alias), or a local user alias per selected account?
4. Should the leading badge be part of the layout token system (e.g. a new `accountBadge` token) instead of a fixed prefix?
5. Should a dedicated issue track per-account items now that #1843 is closed?
