# Animation implementation plans

| # | Plan | Severity | Status | Depends on |
|---|---|---|---|---|
| 001 | [Add native completion undo and redo](001-native-completion-undo.md) | HIGH | DONE | — |
| 002 | [Acknowledge completion before hiding the row](002-stage-completion-exit.md) | HIGH | DONE | 001 |

## Recommended execution order

1. Apply plan 001 so every completion mutation, including undo and redo, travels through one controller/model path.
2. Apply plan 002 on top of that path so mouse completion, Command-Return, undo, and redo all coordinate with the same staged exit state.

Both plans intentionally preserve `model.items` order and keep the eye toggle out of undo history.
