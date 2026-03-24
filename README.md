# cybros

`cybros` is a monorepo for Core Matrix, a single-installation agent-kernel
product, and its companion agent programs such as Fenix.

## Products

- `Core Matrix` is the kernel product. It owns agent-loop execution,
  conversation state, workflow scheduling, human-interaction primitives,
  runtime supervision, and platform-level governance.
- `Fenix` is the default out-of-the-box agent program. It is both a usable
  assistant product and the first technical validation program for the Core
  Matrix loop.

## Documentation Lifecycle

Work moves through the documentation tree in this order:

1. `docs/proposed-designs`
2. `docs/proposed-plans`
3. `docs/future-plans`
4. `docs/plans`
5. `docs/finished-plans`
6. `docs/archived-plans`

Use `docs/design` for approved design baselines that should remain stable across
multiple future phases. Use `docs/future-plans` for accepted later-phase work
that is intentionally not active yet.

## Current Direction

- `Phase 1` is the current substrate implementation batch for `core_matrix`.
- `Phase 2` is the next platform phase: prove the real agent loop end to end.
- `Phase 3` makes the product usable through Web UI.
- Later phases widen the product boundary through additional validation
  programs, triggers, channels, and eventually extensions.

## Validation Rule

Loop-related work is not complete with automated tests alone. When a phase
claims real loop behavior, validation must include:

- unit and integration coverage
- `bin/dev`
- a real LLM API
- manual validation flows maintained under `docs/checklists`
