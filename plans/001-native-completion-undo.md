# 001 — Add native completion undo and redo

- **Status**: DONE
- **Commit**: fe9e924
- **Severity**: HIGH
- **Category**: Interruptibility
- **Estimated scope**: 3 files, roughly 70 lines

## Problem

Task completion mutates persistent state directly and has no inverse operation registered with AppKit. The accessory-style app also has no command handler for Undo or Redo, so Command-Z and Shift-Command-Z do nothing.

```swift
// Empy Tood/StickyModel.swift:142 — current
func toggle(_ id: UUID) {
    guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
    items[idx].isDone.toggle()
    items[idx].completedAt = items[idx].isDone ? Date() : nil
    onChange?()
}
```

```swift
// Empy Tood/StickyRootView.swift:397 — current
private func toggleDone(_ item: TodoItem) {
    let wasDone = item.isDone
    let itemIndex = model.items.firstIndex(where: { $0.id == item.id })
    withAnimation(.easeInOut(duration: 0.35)) {
        model.toggle(item.id)
    }
    // focus handoff omitted
}
```

## Target

Each sticky owns an independent `UndoManager`. Completing or reopening a task registers the exact prior `isDone` and `completedAt` values. Command-Z restores them; Shift-Command-Z reapplies them. Every undo or redo persists through the existing `model.onChange` callback. Eye visibility is view state and must never enter undo history.

The controller exposes one completion entry point used by both mouse and Command-Return:

```swift
func toggleDone(_ id: UUID) {
    guard let item = model.items.first(where: { $0.id == id }) else { return }
    setDone(id, isDone: !item.isDone, completedAt: item.isDone ? nil : Date())
}
```

Its private setter registers the inverse before calling the model setter. Calling the same setter while undoing automatically registers redo with `UndoManager`.

## Repo conventions to follow

- `StickyController` already owns AppKit-only window behavior and the local key monitor in `Empy Tood/StickyController.swift:12-184`; keep `UndoManager` and Command-Z routing there.
- `StickyModel` owns persisted task mutations and calls `onChange?()` after every mutation in `Empy Tood/StickyModel.swift:98-157`; add an exact-value setter there instead of mutating `items` from the controller.
- `StickyRootView` already routes completion through one local `toggleDone(_:)` helper from both checkbox click and Command-Return in `Empy Tood/StickyRootView.swift:343-365`.

## Steps

1. In `Empy Tood/StickyModel.swift`, add an `@ObservationIgnored` callback `onWillSetDone: ((UUID, Bool) -> Void)?`. Add `setDone(_ id: UUID, isDone: Bool, completedAt: Date?)` that calls this callback before changing the matching item, assigns both exact values, and calls `onChange?()`. Make the existing `toggle(_:)` delegate to this setter or retire it if no callers remain.
2. In `Empy Tood/StickyController.swift`, add a private `UndoManager` owned for the controller lifetime. Implement `windowWillReturnUndoManager(_:)` so the sticky window’s responder chain returns that manager.
3. Add `toggleDone(_ id: UUID)` and a private exact-value `setDone` helper to `StickyController`. Before mutation, capture both prior values, register an undo closure targeting the controller that calls the exact-value helper with those captured values, set the action name to `Complete Task` or `Reopen Task`, then call `model.setDone`.
4. In the controller’s local key monitor, before the existing Command-N/D/V handling, intercept Command-Z with no Shift as undo and Command-Shift-Z as redo. Return `nil` only when the corresponding operation is available and performed; otherwise return the original event.
5. In `Empy Tood/StickyRootView.swift`, replace direct `model.toggle(item.id)` usage with `controller.toggleDone(item.id)`. Do not register the eye toggle with undo.
6. Verify an undo after persistence scheduling still restores state and schedules another save. Verify each sticky has isolated history.

## Boundaries

- Do NOT make text editing, adding, deleting, color, font, title, archive, or eye visibility undoable in this change.
- Do NOT reorder `model.items` under any path.
- Do NOT add a toast, banner, or new visible control.
- Do NOT add dependencies.
- If the cited completion flow no longer matches commit `fe9e924` plus the current dirty `StickyRootView.swift`, STOP and report instead of improvising.

## Verification

- **Mechanical**: run `xcodebuild -project 'Empy Tood.xcodeproj' -scheme 'Empy Tood' -configuration Debug -derivedDataPath /tmp/empy-tood-completion-undo CODE_SIGNING_ALLOWED=NO build`; expect `BUILD SUCCEEDED`.
- **Feel check**: run the app and confirm:
  - Complete tasks at the first, middle, and last positions; Command-Z restores each at its original index.
  - Shift-Command-Z completes the restored task again without moving any task.
  - Undo on one sticky does not change another sticky.
  - Toggling the eye and pressing Command-Z does not reverse eye visibility.
  - Rapid Undo/Redo never creates duplicate rows or loses task text.
- **Done when**: completion and reopening form a stable native undo/redo chain, preserve exact ordering, and persist after relaunch.
