# Selected account status items: implementation notes

The Core slice is unchanged. The app integration uses the existing planner, zero-width status-item
factory, placement preservation, validated retained account snapshots, layout renderer and menu rebuild lifecycle.
Selections are local JSON under `selectedAccountIconsV1`; saved Merge Icons suppresses expansion without erasing intent.
Unsupported settings versions remain read-only. Missing usage is never filled from the active provider snapshot.

## Changed files

- `Sources/CodexBar/PreferencesProviderDetailView.swift`
- `Sources/CodexBar/PreferencesSelectedAccountIconsSection.swift`
- `Sources/CodexBar/SettingsStore+MenuObservation.swift`
- `Sources/CodexBar/SettingsStore+SelectedAccountIcons.swift`
- `Sources/CodexBar/SettingsStore.swift`
- `Sources/CodexBar/SettingsStoreState.swift`
- `Sources/CodexBar/StatusItemController+AccountMenuDisplay.swift`
- `Sources/CodexBar/StatusItemController+AccountRendering.swift`
- `Sources/CodexBar/StatusItemController+AccountStatusItems.swift`
- `Sources/CodexBar/StatusItemController+CountdownRefresh.swift`
- `Sources/CodexBar/StatusItemController+IconObservation.swift`
- `Sources/CodexBar/StatusItemController+MenuBarLayout.swift`
- `Sources/CodexBar/StatusItemController+Menu.swift`
- `Sources/CodexBar/StatusItemController+MenuContexts.swift`
- `Sources/CodexBar/StatusItemController+MenuTracking.swift`
- `Sources/CodexBar/StatusItemController+SelectedAccountMenu.swift`
- `Sources/CodexBar/StatusItemController+Shutdown.swift`
- `Sources/CodexBar/StatusItemController+StatusItemVending.swift`
- `Sources/CodexBar/StatusItemController.swift`
- `Sources/CodexBar/UsageStore+AccountRefreshPolicy.swift`
- `Sources/CodexBar/UsageStore+SelectedAccountIconRendering.swift`
- `Sources/CodexBar/UsageStore+SelectedAccountIcons.swift`
- `Sources/CodexBar/UsageStore+TokenAccounts.swift`
- `Sources/CodexBar/UsageStore+WidgetAccounts.swift`
- `Sources/CodexBar/UsageStore.swift`
- `Tests/CodexBarTests/SelectedAccountIconsLifecycleTests.swift`
- `Tests/CodexBarTests/SelectedAccountIconsProjectionTests.swift`
- `Tests/CodexBarTests/SelectedAccountIconsSettingsTests.swift`
- `docs/selected-account-status-items-impl-notes.md` (this file)

## Implementation boundaries

- Inventory reads cached Claude adapter rows, cached Codex visible-account projection and validated token caches.
  Codex eligibility requires a managed-account source UUID; profile/system rows are disabled in Preferences.
  Codex cached usage must pass the existing account/workspace/auth ownership matcher.
- Account items register before factory callbacks can reenter. Reconciliation retains existing identities on reorder;
  explicit provider reordering, recovery and shutdown include account items. Provider and account placement names
  remain independent. Account menus and focus registrations are removed with each item.
- Account rendering has an identity-specific `iconKey`, account snapshot, semantic windows and stale option. It
  uses the existing layout renderer and meter/critter renderer, including provider/global/legacy layout resolution.
  Provider costs, credits and pace/history fields are intentionally unavailable in this projection.
- Menu focus is carried as `ProviderAccountIdentity` in rebuild/card contexts and retained by menu identity.
  Cards put the focused account first, including an unavailable placeholder if it disappears while tracking.
  Last-known usage supplies the existing card age field. Opening a focused menu invokes no selection setter;
  active-account switchers and provider-level web/history extras are omitted from that focused presentation.
- Selected token/managed account demand precedes other consumers, followed by the followed account, within six slots.
  Remaining consumers keep their existing order. Off-mode admission follows the original code paths. The existing
  provider scheduler, manual mode and PAT guard remain the owners of whether refresh occurs; no timer or endpoint
  was added. Claude continues its existing bounded adapter list refresh.

## Verification performed on Linux

With `PATH=/workspace/tools/swift-6.2-RELEASE-debian12/usr/bin:$PATH`:

```sh
swift build --build-tests
swift test --skip-build --filter SelectedAccountIcons
```

Both passed; the selected Core suite has eight tests. These commands do **not** compile the macOS app or its tests.
Changed Swift files also passed `swiftc -frontend -parse -enable-bare-slash-regex` (syntax only).
SwiftFormat 0.63.0 was applied only to touched files. SwiftLint 0.65.1 static lint on touched Swift files reports
zero violations; its SourceKit-dependent `literal_expression_end_indentation` and `statement_position` rules were
skipped by that Linux binary. The nonstatic binary could not create its wakeup socket and was stopped.
`git diff --check` passed. `make check` was attempted and could not start because `make` is absent.
No credentials, Keychain reads, live provider probes, account switching, packaging or app launches were performed.
No commit was made.

## macOS compilation and behavior still to verify

All app changes and app tests require macOS type checking. In particular, verify SwiftUI's section/picker and
nested enumerated `ForEach` expressions, Observation tracking through `SettingsDefaultsState`, memberwise menu
context initializers with the new optional focus, nested status identity isolation after moving it beside the
factory, and generic admission inference. The called APIs were traced to existing definitions; Linux syntax
parsing cannot establish AppKit/SwiftUI availability or Swift 6 actor correctness.

The new focused tests cover settings observation/restart/future payloads, retained inventory, managed UUID ownership,
profile exclusion, token UUID identity, unavailable render inputs, focus without activation, six-slot admission,
factory registration ordering, reorder retention and teardown reconciliation. They do not prove live AppKit
tracking, Control Center recovery, shutdown side effects or physical placement on a display. Those need a synthetic
fresh-bundle check on macOS. No screenshot/runtime proof can be produced on this Linux host.

Run these exact commands from the checkout on macOS, with the repository's normal Swift/toolchain setup:

```sh
swift build --build-tests
CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1 make test-fast FILTER='SelectedAccountIcons|StatusItemCreationOrdering|StatusItemControllerSplitLifecycle|StatusItemControllerShutdown|MenuBarStatusItemPlacementPreservation|MenuBarLayoutRenderer|MenuBarMetricWindowResolver'
make check
```

For a synthetic fixture-only UI session, build the current bundle with `./Scripts/compile_and_run.sh`, then verify
replacement/restore, saved Merge Icons conflict, four-account cap, privacy labels, custom layouts, focused menu
rebuilds, independent placement across relaunch/recovery and teardown. Use fake accounts and injected stores only;
never run real-account usage, cookie imports or live probes for this verification. Capture the display before any
menu-bar automation and verify the visible icon is within screen bounds. Full-suite coverage can remain with PR CI;
do not block the handoff on a foreground full suite.

## Review pass

Reviewed `git diff upstream/main...HEAD -- Sources Tests` file by file, then reviewed the
additional integration fixes below. This is a declaration-based review on Linux, not a
claim that the macOS target has passed a Swift compiler. Repository declarations were
located with `rg`; Apple SDK declarations are unavailable on this host.

### Declaration and integration audit

Paths in this table are relative to `Sources/CodexBar` unless stated otherwise.

| File | Verification |
| --- | --- |
| `PreferencesProviderDetailView.swift` | Section initializer matches provider, UsageStore and SettingsStore types; caller is main-actor isolated. |
| `PreferencesSelectedAccountIconsSection.swift` | Bindable models are Observable/main-actor; Picker mode is Hashable; enumerated IDs and key IDs are Hashable; Binding setters use normalized settings; managedAccount pattern matches CodexActiveSource. |
| `SettingsStore+MenuObservation.swift` | New property resolves to the internal settings extension and observes defaultsState. |
| `SettingsStore+SelectedAccountIcons.swift` | Data persistence API, public load/encode/setEntry APIs, optional entry lookup and read-only guards match declarations. |
| `SettingsStore.swift` | Mutable local defaults state is initialized before assignment; existing memberwise defaults-state initializer can omit the new default-valued field. |
| `SettingsStoreState.swift` | Core settings type is imported and Sendable; no new Equatable/Hashable requirement on settings state. |
| `StatusItemController+AccountMenuDisplay.swift` | Updated limitedTokenAccounts call matches accounts/selected/provider labels and argument order. |
| `StatusItemController+AccountRendering.swift` | Traced layout resolution, render data/options initializers, render/apply APIs, brand/meter icon APIs, optional percentages, semantic windows, predicates and reset fields. Optional PercentWindow switch covers session/weekly/scopedWeekly/automatic/spend/nil. Predicate switch intentionally returns nil for unsupported metrics. |
| `StatusItemController+AccountStatusItems.swift` | Factory closure types, dictionary key/value types, menu registration/removal, placement helpers, Set subtraction, planner cases and creation ordering match declarations. |
| `StatusItemController+CountdownRefresh.swift` | Added tuple members match Date arrays and TimeInterval delays; empty account registry adds no countdown demand. |
| `StatusItemController+IconObservation.swift` | Signature helper is unique and accessible in another extension; inventory signature now includes aliases. |
| `StatusItemController+Menu.swift` | Traced focus through rebuild/card contexts, menu map keys, switcher suppression and capture-menu paths. Existing optional context fields have implicit nil defaults in synthesized memberwise initializers. |
| `StatusItemController+MenuBarLayout.swift` | Account rendering call runs under the controller's main actor and shutdown guard. |
| `StatusItemController+MenuContexts.swift` | ProviderAccountIdentity is public, Hashable and Sendable; optional focus fields do not make existing initializer calls require another argument. |
| `StatusItemController+MenuTracking.swift` | Combined status-item value arrays have the same NSStatusItem element type; attached-menu enumeration includes account menus. |
| `StatusItemController+SelectedAccountMenu.swift` | Focus/key conversions, account card context initializer order, unavailable history selection, privacy ordinal, stacked card API and optional last-known date match declarations. |
| `StatusItemController+Shutdown.swift` | New cleanup method is internal/main-actor and runs before other status items are removed. |
| `StatusItemController+StatusItemVending.swift` | Both StatusItemIdentity switches include account; moved private identifier prefix is used only within its file; factory generic still requires StatusItemConfiguring; callback registration remains before sizing. |
| `StatusItemController.swift` | New dictionaries have Hashable keys; planner switch is exhaustive; provider replacement, recovery, reordering and shutdown include account items; legacy provider/merged names are unchanged. |
| `UsageStore+AccountRefreshPolicy.swift` | Generic IDs are constrained Hashable; UUID and String inference matches both callers; followedID optionality, PAT guard, six-slot prefix and legacy admission branches were traced. |
| `UsageStore+SelectedAccountIconRendering.swift` | All render-data initializer labels/order and omitted defaulted fields match MenuBarLayoutRenderData; failable window initializers receive optional RateWindow; metrics.unavailable is internal and accessible. |
| `UsageStore+SelectedAccountIcons.swift` | Traced ProviderAccountUsageSnapshot, ProviderAccountIdentity, CodexVisibleAccount, CodexAccountUsageSnapshot, token snapshot/cache APIs and managed UUID identity. Ownership matcher is nonisolated/internal and accessible. |
| `UsageStore+TokenAccounts.swift` | Moved limiter declarations have no remaining duplicate; updated calls retain labels/defaults and the original off-mode guards. |
| `UsageStore+WidgetAccounts.swift` | New provider argument matches the limiter; widget consumers still share six-slot admission. |
| `UsageStore.swift` | Observation touches existing account snapshot dictionaries only for saved selected-account mode; store remains main-actor Observable. |
| `Sources/CodexBarCore/SelectedAccountIcons.swift` | Real Linux type checking covers Codable/Sendable, private JSONValue, Hashable keys, Equatable entries/planned items, exhaustive enum switches, normalization and hashing. Raw-value mode supports Picker Hashable/Equatable requirements. |
| `Tests/CodexBarTests/SelectedAccountIconsLifecycleTests.swift` | Matches neighboring Swift Testing suites, sentence test names and main-actor fake StatusItemConfiguring; factory generic and internal APIs are available via testable import. |
| `Tests/CodexBarTests/SelectedAccountIconsProjectionTests.swift` | Traced UsageStore testing initializer, snapshots, cached projection, fixture account initializers, generic admission, card model and injected defaults; no live account or AppKit menu construction. |
| `Tests/CodexBarTests/SelectedAccountIconsSettingsTests.swift` | Matches Swift Testing style; injected dictionary defaults/noop stores use existing test helper; observation callback captures only a lock-protected unchecked-Sendable flag. |
| `StatusItemController+Actions.swift` (review fix) | Shortcut and celebration origin first resolve an existing account item; nil-coalescing preserves lazy provider vending when no account item exists. |
| `UsageStore+MenuCardModel.swift` (review fix) | Optional account label defaults nil in memberwise context initializer; passes through the explicit Input initializer after privacyOrdinal. |
| `MenuCardView+ModelInput.swift` (review fix) | New optional label override has a defaulted argument, initialized storage, and no added generic/conformance requirements. |
| `MenuCardView.swift` (review fix) | Explicit override precedes snapshot email lookup; existing callers receive nil and retain prior behavior. |

No repository-level unresolved type/label/access mismatch was found in this audit. Controller,
settings and store operations inherit their enclosing types' MainActor isolation. New closures
are synchronous and nonescaping except the observation callback, whose captured flag uses a
lock. No new async-let siblings or actor-crossing account objects were introduced. Searches
found one declaration each of the new model/helper names; private JSONValue stays in Core's
file, and no new cross-file access to private/fileprivate members was identified.

### Design checks and fixes

- Off mode retains provider/merged names and item vending; no account items/countdown dates are
  admitted. Token and Codex limiters retain the original branch when demand is empty. Saved
  Merge Icons suppresses keys/planning even with one enabled provider, without clearing intent.
- Four accounts per provider are enforced by normalization on construction, decoding and edits,
  as well as Preferences. Unavailable selections remain saved but can now be deselected;
  previously their read-only text could trap all four slots.
- Reconciliation now restores visibility for retained account items, including recovery after
  the existing hide/show recovery path. Previously only newly created items were shown.
- Alias changes now participate in the icon work signature; previously unchanged usage could
  leave the old label rendered.
- Keyboard shortcuts and celebration origin lookup now reuse an account item rather than
  vending a replacement provider icon beside the selected account icons.
- Nonselected focused-menu cards now receive distinct fallback ordinals instead of all using
  Account 1. Selected cards retain their saved ordinals.
- Focused menu cards now pass an explicit privacy-filtered label override and privacy ordinal.
  The previous AccountInfo fallback lost to snapshot email lookup and disappeared under Hide
  Personal Info. Added synthetic card assertions for alias precedence and hidden-info ordinal.
- Opaque source identities drive hashed autosave/accessibility IDs; email-like aliases are
  rejected before truncation. Display labels never enter autosave names.
- Opening/rebuilding account menus reads focus and snapshots, supplies a missing-account
  placeholder, and invokes no active-account selection setter. Account switchers and provider
  web/history extras are suppressed. Added a removed-focus placeholder/purity assertion and
  a regression test for off-mode/saved-merge versus selected token refresh admission.
- Fixed SwiftFormat violations in Core's single-line computed properties; no semantic change.

### Checks and remaining uncertainty

Final checks cover all 33 changed Swift files (original comparison plus review fixes):

- `swift build --build-tests`: passed with Swift 6.2 on Linux.
- `swift test --skip-build --filter SelectedAccountIcons`: passed, eight Core tests.
- `/workspace/tools/swiftformat_linux --lint <files>`: passed.
- `/workspace/tools/swiftlint-static lint --strict <files>`: zero violations, but the initial
  command could not write its cache under `/var/tmp`. Rerun with
  `--cache-path /tmp/codexbar-review-swiftlint` passed. The static binary skips the two
  SourceKit-dependent rules described above.
- `swiftc -frontend -parse -enable-bare-slash-regex <files>`: passed (syntax only).
- `git diff --check`: passed. `make check` remains unavailable: `make` is not installed.

Remaining uncertainties, highest risk first:

1. **High: macOS compilation.** Linux excludes the app and all three app test suites. Apple
   SDK overload selection, SwiftUI result-builder inference and SDK actor annotations still
   require a macOS build. Manual declaration tracing cannot certify these or substitute for
   Swift 6 strict-concurrency type checking of the app. The added regression tests have not
   executed on this host.
2. **Medium: AppKit lifecycle.** Actual tracking/reentrant callbacks, physical placement,
   shortcut clicking, Control Center recovery and shutdown need the synthetic macOS checks
   above. The retained-item visibility and duplicate-vending fixes have static verification,
   not runtime UI proof.
3. **Low: presentation parity.** Font/layout/high-contrast rendering and accessibility speech
   need macOS inspection. Off-mode item names/admission paths are preserved by source review;
   byte-identical rendered output has not been measured on macOS.

No credentials, live probes, Keychain operations, app launches, packaging or commits were used.
