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
