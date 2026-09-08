# Explicit Search And Minimal Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove ambiguous letter shortcuts from the Command-Tab switcher, make Control-Space the explicit conflict-free search entry point, and remove the direct-typing setting.

**Architecture:** Keep Command-Tab focused on recent-window cycling and the existing Command-W/M/H/Q window actions. Search remains an explicit `SwitcherMode.search` presentation from Control-Space or the menu, where the global input handler captures unmodified text while no cycling modifier is active. Remove the now-unused search-transition protocol path and direct-typing setting, then update the settings, footer, documentation, and tests to describe the simplified interaction.

**Tech Stack:** Swift 5.9+, AppKit global CGEvent tap, SwiftUI, XCTest, Swift Package Manager.

---

### Task 1: Simplify keyboard routing

**Files:**
- Modify: `Sources/QuickTab/GlobalInputController.swift`
- Modify: `Sources/QuickTab/AppCoordinator.swift`
- Test: `Tests/QuickTabTests/GlobalInputControllerTests.swift`

- [x] **Step 1: Add regression coverage for letter passthrough during a visible Command-Tab session**

Add a test that presents a cycling switcher, sends `s`, `j`, and `k` with Command held and text attached, then verifies all three events pass through and no query or selection movement is recorded. Preserve the existing Command-W/M/H/Q tests as the action contract.

- [x] **Step 2: Run the focused tests and verify the new test fails**

Run: `swift test --filter GlobalInputControllerTests`

Expected: the new test fails because `s` currently calls `beginSwitcherSearch` and `j`/`k` currently move selection.

- [x] **Step 3: Remove the reserved `s`, `j`, and `k` paths**

In `GlobalInputController`:

```swift
// Remove beginSwitcherSearch() from GlobalInputHandler.
// Remove the keyCode.s special case.
// Change the navigation switch to arrows only.
case KeyCode.up:
    enqueueHandlerWork { $0.moveSwitcherSelection(by: -1) }
    return true
case KeyCode.down:
    enqueueHandlerWork { $0.moveSwitcherSelection(by: 1) }
    return true
```

Delete the unused `KeyCode.s`, `KeyCode.j`, and `KeyCode.k` constants. Remove the matching forwarding method from `AppCoordinator`.

- [x] **Step 4: Run the focused tests and verify the behavior passes**

Run: `swift test --filter GlobalInputControllerTests`

Expected: all focused tests pass, including the new passthrough test and the existing Command-W/M/H/Q action tests.

### Task 2: Remove the direct-typing setting

**Files:**
- Modify: `Sources/QuickTab/SettingsStore.swift`
- Modify: `Sources/QuickTab/GlobalInputController.swift`
- Modify: `Sources/QuickTab/AppCoordinator.swift`
- Modify: `Sources/QuickTab/SettingsView.swift`
- Modify: `Tests/QuickTabTests/GlobalInputControllerTests.swift`

- [x] **Step 1: Remove the setting from persistence and configuration**

Delete the `directTyping` key, published property, default registration, load/save calls, and `GlobalInputConfiguration.directTyping`. Stop passing it from `AppCoordinator.updateInputConfiguration()`.

- [x] **Step 2: Make explicit search the only query-entry route**

Keep the existing Control-Space branch before switcher routing so it presents `.search` and remains active for the immediately following character. Remove the `configuration.directTyping` fallback from the visible-switcher key handling. The fallback should return `false` for ordinary letters in Command-Tab mode, allowing the underlying app to receive them rather than silently changing the selected-window search state.

Retain a query fallback only when no cycling modifier is active, so explicit `.search` presentations still capture unmodified text:

```swift
if cyclingModifier == nil,
   let text = event.text,
   !text.isEmpty {
    enqueueHandlerWork { $0.appendSwitcherQuery(text) }
    return true
}
return false
```

- [x] **Step 3: Update settings UI**

Remove the `Type to search while switching` toggle from the Switchers settings group. Leave the existing Window Search, Current App, and Fast Search controls in place.

- [x] **Step 4: Update tests for the removed configuration**

Remove tests that construct `GlobalInputConfiguration(directTyping: false)`. Add assertions that ordinary characters are passed through during Command-Tab mode, while keeping the Control-Space presentation/query test to verify explicit search still accepts its first character.

- [x] **Step 5: Run the focused tests**

Run: `swift test --filter GlobalInputControllerTests`

Expected: all focused tests pass with no references to `directTyping` remaining in source or tests.

### Task 3: Make explicit search state clearer

**Files:**
- Modify: `Sources/QuickTab/SwitcherView.swift`
- Modify: `Sources/QuickTab/README.md`
- Modify: `Sources/QuickTab/PermissionView.swift` only if the existing search shortcut copy needs matching wording

- [x] **Step 1: Improve the search-state copy without changing layout structure**

Keep the existing `WINDOW SEARCH` mode label, but update the empty-search prompt to clearly instruct the user to type an app or window name. Update the footer so explicit search is discoverable while the switcher is open, without adding letter shortcuts.

- [x] **Step 2: Update the controls documentation**

Document arrows as the only movement keys, retain Return/Escape/Delete and Command-W/M/H/Q, and state that Control-Space opens search. Remove any wording that claims typing during Command-Tab is a supported search path.

- [x] **Step 3: Run source searches for stale shortcut references**

Run:

```bash
rg -n "directTyping|beginSwitcherSearch|KeyCode\.(s|j|k)|\bJ\b|\bK\b|Type to search while switching" Sources Tests README.md
```

Expected: no stale implementation or UI/documentation references remain, except intentional test names or historical plan text if any.

### Task 4: Full verification and pull request

**Files:**
- Review: all modified files and `docs/superpowers/plans/2026-09-08-search-shortcuts-plan.md`

- [x] **Step 1: Run the complete test suite**

Run: `swift test`

Expected: all tests pass.

- [x] **Step 2: Inspect the final diff and repository state**

Run: `git status --short`, `git diff --check`, and `git diff --stat`.

Expected: only the shortcut/search implementation, tests, documentation, and implementation plan are included; no generated build or secret files are present.

- [ ] **Step 3: Commit the feature branch**

Run: `git add Sources Tests README.md docs/superpowers/plans/2026-09-08-search-shortcuts-plan.md && git commit -m "fix: simplify switcher shortcuts"`

- [ ] **Step 4: Push the feature branch and open the pull request**

Run: `git push -u origin feat/search-shortcut-cleanup` followed by `gh pr create --base main --head feat/search-shortcut-cleanup --title "fix: simplify switcher shortcuts" --body "## Summary\n\n- Make Control-Space the explicit, conflict-free search entry point.\n- Remove J/K/S and the Type to search while switching setting.\n- Preserve Command-W/M/H/Q window actions.\n- Clarify the search UI and controls documentation.\n\n## Verification\n\n- swift test"`.

The pull request body should summarize explicit Control-Space search, removal of J/K/S/direct typing, preserved Command-W/M/H/Q actions, updated UI copy, and `swift test` verification.
