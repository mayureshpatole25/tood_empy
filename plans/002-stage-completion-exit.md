# 002 — Acknowledge completion before hiding the row

- **Status**: DONE
- **Commit**: fe9e924
- **Severity**: HIGH
- **Category**: Purpose & frequency, Easing & duration, Accessibility
- **Estimated scope**: 1 file, roughly 80 lines

## Problem

Completing a hidden-done task changes model state and list membership inside one slow 350ms transaction. The row cannot visibly show its checked state before it begins disappearing, and the subsequent focus change triggers a separate 160ms scroll animation. The result feels both abrupt and sluggish.

```swift
// Empy Tood/StickyRootView.swift:397 — current
private func toggleDone(_ item: TodoItem) {
    let wasDone = item.isDone
    let itemIndex = model.items.firstIndex(where: { $0.id == item.id })
    withAnimation(.easeInOut(duration: 0.35)) {
        model.toggle(item.id)
    }

    guard !wasDone, !showsDoneTasks, focusedID == item.id, let itemIndex else { return }
    focusedID = model.items[(itemIndex + 1)...].first(where: { !$0.isDone })?.id
        ?? model.items[..<itemIndex].last(where: { !$0.isDone })?.id
}
```

The eye toggle also mixes focus clearing and visibility inside a weak symmetric animation:

```swift
// Empy Tood/StickyRootView.swift:464 — current
withAnimation(.easeInOut(duration: 0.2)) {
    // focus mutation
    showsDoneTasks.toggle()
}
```

## Target

Use a staged, interruptible completion exit:

1. The model becomes done immediately, rendering the filled checkbox, strikethrough, and secondary ink without delay.
2. When done rows are hidden, retain that row in the rendered collection for a 120ms acknowledgement hold.
3. Remove only that retained ID over 180ms with a strong ease-out timing curve:

```swift
Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
```

4. The row uses an opacity removal transition; the `LazyVStack` closes the vacated space in the same transaction. No scale, bounce, blur, or reorder is introduced.
5. The eye toggle uses the same strong ease-out family over 200ms:

```swift
Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)
```

6. With Reduce Motion enabled, skip the 120ms hold and all positional animation; update visibility immediately.
7. Undo/reopen cancels a pending exit and makes the original row visible at its original model index. Redo starts a fresh acknowledgement/exit sequence.

## Repo conventions to follow

- `StickyRootView` keeps transient per-sticky UI state in `@State` properties at `Empy Tood/StickyRootView.swift:10-17`.
- Persisted ordering comes exclusively from `model.orderedItems`; `displayedItems` at `Empy Tood/StickyRootView.swift:295-300` may filter visibility but must never sort, partition, append, or group.
- Model-to-view callbacks are `@ObservationIgnored` bridges configured in `.onAppear`, as used throughout `Empy Tood/StickyModel.swift:45-63` and `Empy Tood/StickyRootView.swift:73-100`.

## Steps

1. In `Empy Tood/StickyRootView.swift`, read `@Environment(\.accessibilityReduceMotion)` and add transient state for a `Set<UUID>` of completion IDs being retained during acknowledgement plus cancellable per-ID `Task<Void, Never>` handles.
2. In `.onAppear`, connect the `model.onWillSetDone` callback added by plan 001 to a new `prepareDoneTransition(id:isDone:)` helper. Clear the callback and cancel outstanding tasks when the view disappears.
3. Change `displayedItems` to include a row only when `showsDoneTasks || !item.isDone || retainedCompletionIDs.contains(item.id)`. This is a single filter over `model.orderedItems`; preserve exact source order.
4. When `prepareDoneTransition` receives `isDone == true` while done rows are hidden, insert the ID into the retained set before the model mutation, cancel any prior task for that ID, and schedule a new main-actor task. Wait exactly 120ms, then remove the retained ID with the 180ms timing curve. Store and later clear the task handle.
5. When `prepareDoneTransition` receives `isDone == false`, cancel and remove any pending task for that ID and remove the ID from the retained set without delay. Because the model is becoming active, the normal filter keeps it visible at its original index.
6. Add `.transition(.opacity)` to the entire row container returned by `row(_:)`; remove the current transition modifier from the nested `TextField` if it no longer serves a purpose. Do not add scale or movement to the row itself.
7. Replace the current 350ms `withAnimation` in `toggleDone(_:)` with a direct call to `controller.toggleDone(item.id)`. If a currently focused row is completed while done rows are hidden, clear its focus without scrolling to another row; do not trigger the checklist’s 160ms focus-scroll animation during exit.
8. For the eye button, clear completed-row focus before the animation transaction. Toggle visibility with the 200ms timing curve. When Reduce Motion is enabled, toggle without `withAnimation`.
9. When Reduce Motion is enabled, `prepareDoneTransition` must not retain the completed ID and must not schedule a task; the row disappears immediately after the model change.
10. Make task cleanup generation-safe: a stale delayed task must never hide a task that was undone and completed again. Cancellation plus identity checking of the stored task/generation is required.

## Boundaries

- Do NOT alter task order, checkbox shape, typography, row spacing, dividers, sticky sizing, or toolbar layout.
- Do NOT animate task text edits, task creation, or focus scrolling.
- Do NOT exceed 200ms for any animated phase.
- Do NOT use springs, bounce, scale, blur, or new dependencies.
- Do NOT animate the eye button when there are zero completed tasks.
- If plan 001 has not been applied or `model.onWillSetDone` is unavailable, STOP and apply plan 001 first.

## Verification

- **Mechanical**: run `xcodebuild -project 'Empy Tood.xcodeproj' -scheme 'Empy Tood' -configuration Debug -derivedDataPath /tmp/empy-tood-completion-motion CODE_SIGNING_ALLOWED=NO build`; expect `BUILD SUCCEEDED`.
- **Feel check**: run the app and confirm:
  - With done rows hidden, clicking a checkbox immediately shows the check and strikethrough, holds briefly, then fades/closes smoothly.
  - The task never moves to a completed group; all remaining tasks retain relative order.
  - Complete first, middle, and last rows and verify the same timing each time.
  - Spam checkbox, Command-Z, and Shift-Command-Z; stale delayed work never removes the wrong state.
  - Rapidly toggle the eye; the transition retargets cleanly without restarting from a stale state.
  - Enable Reduce Motion in macOS Accessibility settings; completion and eye visibility update immediately without positional movement.
- **Done when**: completion is visibly acknowledged before exit, list order never changes, undo cancels or reverses exit reliably, and Reduce Motion removes movement.
