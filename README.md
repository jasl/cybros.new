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

- The current substrate batch continues to harden `core_matrix` foundations.
- The current agent-loop validation batch proves the real loop end to end.
- The next product batch makes the system usable through Web UI.
- Later batches widen the product boundary through additional validation
  programs, triggers, channels, and eventually extensions.

## Validation Rule

Loop-related work is not complete with automated tests alone. When a phase
claims real loop behavior, validation must include:

- unit and integration coverage
- `bin/dev`
- a real LLM API
- manual validation flows maintained under `docs/checklists`

## Licensing

Licensing in this monorepo is project-scoped.

- Repository-root materials that are not covered by a more specific
  subdirectory license are licensed under the O'Saasy License Agreement. See
  [LICENSE.md](/Users/jasl/Workspaces/Ruby/cybros/LICENSE.md).
- [core_matrix](/Users/jasl/Workspaces/Ruby/cybros/core_matrix) and each
  standalone project under
  [agents/](/Users/jasl/Workspaces/Ruby/cybros/agents) are licensed under the
  O'Saasy License Agreement, as stated in the license file at the root of the
  relevant project.
- [core_matrix/vendor/simple_inference](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference)
  is a separately licensed vendored gem and remains licensed under the MIT
  License. See
  [LICENSE.txt](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/LICENSE.txt).
- Where a subdirectory contains its own license file, that subdirectory-specific
  license controls for the contents of that subdirectory.
